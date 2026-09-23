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

Why it is careful
    The load is a DELETE followed by an INSERT, staged through temporary tables
    and committed once, so an interrupted run leaves the previous fixture intact.
    It targets a disposable demo database, so there are no ownership or marker
    checks -- only the schema contract check, which prevents a positional INSERT
    from loading values into the wrong columns.
"""

from datetime import date
from decimal import Decimal

from generate_cowork import FIELDS, RELEASE, observations, validate


SCHEMA = 'SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY'


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
    for name, rows in tables.items():
        target = f'{SCHEMA}.{name}'
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
