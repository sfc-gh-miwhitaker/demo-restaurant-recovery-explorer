"""Deployment helper executed in Snowflake, never on the business agent's behalf."""

from datetime import date
from decimal import Decimal

from generate_cowork import FIELDS, RELEASE, observations, validate


SCHEMA = 'SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY'


def require_demo_object(session, kind, name, schema):
    rows = session.sql(f'SHOW {kind} IN SCHEMA {schema}').collect()
    for row in rows:
        values = row.as_dict()
        if values['name'] == name:
            if values.get('owner') != 'SYSADMIN' or 'DEMO:' not in (values.get('comment') or ''):
                if kind != 'SEMANTIC VIEWS' or values.get('owner') != 'SYSADMIN' or 'Synthetic restaurant recovery' not in (values.get('comment') or ''):
                    raise ValueError(f'{name} is not marked as this demo; review collision')


def seed(session):
    from snowflake.snowpark.types import DateType, DecimalType

    # Snowpark's overwrite write issues an unqualified DROP, so the caller-rights
    # session needs an explicit current database and schema.
    session.sql(f'USE SCHEMA {SCHEMA}').collect()
    tables = observations()
    validate(tables)
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
        invalid = session.sql(f'SELECT COUNT(*) FROM {target} WHERE RELEASE_ID IS NULL OR RELEASE_ID <> ?', params=[RELEASE]).collect()[0][0]
        if invalid:
            raise ValueError(f'{name} contains another release; refusing replacement')
        if name == 'RELEASE_METADATA':
            if session.sql(f'SELECT COUNT(*) FROM {target} WHERE SYNTHETIC IS DISTINCT FROM TRUE').collect()[0][0]:
                raise ValueError('Non-synthetic data found; refusing replacement')
        schema = session.table(target).schema
        if [field.name for field in schema.fields] != FIELDS[name]:
            raise ValueError(f'{name} schema differs from the canonical contract')
        converted = []
        for row in rows:
            values = []
            for field in schema.fields:
                value = row[field.name]
                if value is not None and isinstance(field.datatype, DateType):
                    value = date.fromisoformat(value)
                elif value is not None and isinstance(field.datatype, DecimalType):
                    value = Decimal(str(value))
                values.append(value)
            converted.append(values)
        session.create_dataframe(converted, schema).write.mode('overwrite').save_as_table(
            f'{SCHEMA}.SEED_{name}', table_type='temporary')
    session.sql('BEGIN TRANSACTION').collect()
    try:
        for name, rows in tables.items():
            columns = ', '.join(FIELDS[name])
            session.sql(f'DELETE FROM {SCHEMA}.{name}').collect()
            session.sql(f'INSERT INTO {SCHEMA}.{name} ({columns}) SELECT {columns} FROM {SCHEMA}.SEED_{name}').collect()
            count = session.sql(f'SELECT COUNT(*) FROM {SCHEMA}.{name}').collect()[0][0]
            if count != len(rows):
                raise ValueError(f'{name} failed row-count verification')
        session.sql('COMMIT').collect()
    except Exception:
        session.sql('ROLLBACK').collect()
        raise
    finally:
        for name in tables:
            session.sql(f'DROP TABLE IF EXISTS {SCHEMA}.SEED_{name}').collect()
    return f'Loaded and validated {RELEASE}'

