"""Deployment helper executed in Snowflake, never on the business agent's behalf.

What this is
    The handler behind the short-lived SEED_DEMO procedure in sql/deploy.sql.
    It generates the fixture with tools/generate_cowork.py -- the same module
    the local tests exercise -- and loads it into the canonical tables.

Where it runs
    Inside Snowflake, as EXECUTE AS CALLER, imported straight from the pinned
    Git commit. Caller's rights matter: the procedure holds no privileges of
    its own, so it can only write what the deploying role could already write.
    An owner's-rights version would be a standing escalation path that
    outlived the deployment. sql/deploy.sql drops the procedure immediately
    after this returns, and never grants it to the reader role -- the agent
    has no path to this code at all.

Why it is defensive
    A seed load is a DELETE followed by an INSERT against well-known object
    names in a shared database. Every check below exists to make sure those
    names still refer to this demo, so that a namespace collision is a failed
    deployment rather than someone else's data being destroyed. The tests are
    ordered cheapest-first and all run before any write.
"""

from datetime import date
from decimal import Decimal

from generate_cowork import FIELDS, RELEASE, observations, validate


SCHEMA = 'SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY'


def require_demo_object(session, kind, name, schema):
    """Raise unless an existing object of this name is demonstrably this demo.

    Absence is fine -- a first deployment has nothing to check. What is not
    fine is an object of the right name that somebody else owns.
    """
    rows = session.sql(f'SHOW {kind} IN SCHEMA {schema}').collect()
    for row in rows:
        values = row.as_dict()
        if values['name'] == name:
            # Two independent signals, both required: SYSADMIN ownership and
            # the 'DEMO:' comment marker this project stamps on everything.
            if values.get('owner') != 'SYSADMIN' or 'DEMO:' not in (values.get('comment') or ''):
                # Semantic views are the documented exception. Their comment
                # comes from the JSON payload's "description" field, which has
                # no room for the marker prefix, so ownership plus the release
                # description is the equivalent proof for them.
                if kind != 'SEMANTIC VIEWS' or values.get('owner') != 'SYSADMIN' or 'Synthetic restaurant recovery' not in (values.get('comment') or ''):
                    raise ValueError(f'{name} is not marked as this demo; review collision')


def seed(session):
    """Generate, verify the target, stage, then swap the fixture in one commit."""
    # Imported inside the function: the Snowpark types are only available in
    # the Snowflake runtime, and importing at module scope would break the
    # local unit tests that import this file to check the deployment logic.
    from snowflake.snowpark.types import DateType, DecimalType

    # Snowpark's overwrite write issues an unqualified DROP, so the caller-rights
    # session needs an explicit current database and schema.
    session.sql(f'USE SCHEMA {SCHEMA}').collect()
    # Generate and validate before touching the account. If the fixture is
    # invalid, the deployment fails having changed nothing.
    tables = observations()
    validate(tables)
    # Collision checks across every object this deployment will replace: the
    # tables it writes, the semantic views the later scripts replace, and the
    # agent. All of it before the first write, so the deployment cannot stop
    # half way and leave the demo in an unusable state.
    for name in tables:
        require_demo_object(session, 'TABLES', name, SCHEMA)
    for suffix in ('PERFORMANCE', 'OPERATIONS', 'COMPARISONS'):
        require_demo_object(session, 'SEMANTIC VIEWS', f'SV_RESTAURANT_RECOVERY_{suffix}', 'SNOWFLAKE_EXAMPLE.SEMANTIC_MODELS')
    existing_agents = session.sql(f'SHOW AGENTS IN SCHEMA {SCHEMA}').collect()
    for row in existing_agents:
        if row['name'] == 'RESTAURANT_RECOVERY_AGENT' and row['owner'] != 'SYSADMIN':
            raise ValueError('Agent ownership differs; refusing replacement')
    for name, rows in tables.items():
        target = f'{SCHEMA}.{name}'
        # Content checks on the live table. Any row from another release means
        # these tables are not exclusively this demo's, and the DELETE below
        # would destroy data this deployment does not own.
        # Bound parameter, not string interpolation, for the release value.
        invalid = session.sql(f'SELECT COUNT(*) FROM {target} WHERE RELEASE_ID IS NULL OR RELEASE_ID <> ?', params=[RELEASE]).collect()[0][0]
        if invalid:
            raise ValueError(f'{name} contains another release; refusing replacement')
        if name == 'RELEASE_METADATA':
            # Belt and braces: the synthetic flag is asserted in the data, and
            # re-checked here, so this loader cannot be pointed at real data.
            # IS DISTINCT FROM is NULL-safe, where <> TRUE would not be.
            if session.sql(f'SELECT COUNT(*) FROM {target} WHERE SYNTHETIC IS DISTINCT FROM TRUE').collect()[0][0]:
                raise ValueError('Non-synthetic data found; refusing replacement')
        # Field names AND their order must match the generator's contract.
        # Order matters because the INSERT below is positional: a reordered
        # table would load values into the wrong columns without any type
        # error to reveal it.
        schema = session.table(target).schema
        if [field.name for field in schema.fields] != FIELDS[name]:
            raise ValueError(f'{name} schema differs from the canonical contract')
        converted = []
        for row in rows:
            values = []
            for field in schema.fields:
                value = row[field.name]
                # The generator emits JSON-safe primitives -- ISO date strings
                # and floats. Converting to date and Decimal here, driven by
                # the live column types, means the target schema decides the
                # types rather than Python inferring them. Decimal via str()
                # avoids inheriting binary float error into a money column.
                if value is not None and isinstance(field.datatype, DateType):
                    value = date.fromisoformat(value)
                elif value is not None and isinstance(field.datatype, DecimalType):
                    value = Decimal(str(value))
                values.append(value)
            converted.append(values)
        # Staged into temporary tables first, so the expensive part -- moving
        # ~130k rows from Python into Snowflake -- happens outside the
        # transaction and keeps the swap below short.
        session.create_dataframe(converted, schema).write.mode('overwrite').save_as_table(
            f'{SCHEMA}.SEED_{name}', table_type='temporary')
    # The swap. DELETE + INSERT rather than a table replace, so the tables
    # keep their identity: existing grants and the views built on them stay
    # valid instead of needing to be re-granted.
    session.sql('BEGIN TRANSACTION').collect()
    try:
        for name, rows in tables.items():
            # Explicit column list on both sides -- never INSERT ... SELECT *.
            columns = ', '.join(FIELDS[name])
            session.sql(f'DELETE FROM {SCHEMA}.{name}').collect()
            session.sql(f'INSERT INTO {SCHEMA}.{name} ({columns}) SELECT {columns} FROM {SCHEMA}.SEED_{name}').collect()
            # Verify inside the transaction, so a short load rolls back rather
            # than leaving a plausible-looking partial fixture in place.
            count = session.sql(f'SELECT COUNT(*) FROM {SCHEMA}.{name}').collect()[0][0]
            if count != len(rows):
                raise ValueError(f'{name} failed row-count verification')
        session.sql('COMMIT').collect()
    except Exception:
        # All tables are consistent or none are. A fixture that is half old
        # and half new would produce paired comparisons across two releases.
        session.sql('ROLLBACK').collect()
        raise
    finally:
        # Temporary tables die with the session anyway; dropping them here
        # keeps a failed deployment from leaving confusing objects behind.
        for name in tables:
            session.sql(f'DROP TABLE IF EXISTS {SCHEMA}.SEED_{name}').collect()
    return f'Loaded and validated {RELEASE}'
