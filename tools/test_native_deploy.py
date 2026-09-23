"""Offline checks for the SQL entry points and Snowflake deployment helper."""

import json
import re
import subprocess
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import native_runtime


ROOT = Path(__file__).resolve().parents[1]


class NativeDeploymentTests(unittest.TestCase):
    def test_deploy_includes_git_setup_without_separate_bootstrap(self):
        text = (ROOT / 'deploy_all.sql').read_text()
        self.assertIn('ALLOWED_AUTHENTICATION_SECRETS = NONE', text)
        self.assertEqual(text.count('https://github.com/sfc-gh-miwhitaker/demo-restaurant-recovery-explorer.git'), 2)
        self.assertFalse((ROOT / 'bootstrap.sql').exists())
        self.assertNotIn("EXECUTE IMMEDIATE FROM './", text)

    def test_deploy_runs_with_run_all_and_no_operator_variables(self):
        text = (ROOT / 'deploy_all.sql').read_text()
        self.assertIn('Run All', text)
        # A variable the operator has to SET by hand would make a pasted Run All
        # abort on its first statement, which is exactly the failure this repo
        # kept shipping. Safety comes from the namespace and teardown, not from
        # a typed confirmation or a pre-deployment gate.
        self.assertNotIn('RR_CONFIRM', text)
        self.assertNotIn('RR_EXPECTED_ACCOUNT', text)
        self.assertIn('"commit_hash"', text)
        self.assertIn('/commits/', text)
        self.assertNotIn('!source', text)
        self.assertLess(text.index('USE WAREHOUSE'), text.index('SHOW GIT BRANCHES'))

    def test_warehouse_timeout_survives_the_seeding_statement(self):
        # The seed procedure builds and loads roughly 420,000 rows in one
        # statement. A short account-style timeout aborts it mid-transaction and
        # looks like a broken repository to whoever pasted the file.
        text = (ROOT / 'deploy_all.sql').read_text()
        timeout = re.search(r'STATEMENT_TIMEOUT_IN_SECONDS = (\d+)', text)
        self.assertIsNotNone(timeout)
        self.assertGreaterEqual(int(timeout[1]), 1800)

    def test_relative_includes_resolve(self):
        import re
        for path in ROOT.rglob('*.sql'):
            for relative in re.findall(r"EXECUTE IMMEDIATE FROM '(\./[^']+)'", path.read_text()):
                self.assertTrue((path.parent / relative).is_file(), (path.name, relative))

    def test_sql_pipeline_order_and_imports(self):
        text = (ROOT / 'sql/deploy.sql').read_text()
        stages = ["./01_setup.sql", "CALL SNOWFLAKE_EXAMPLE.RESTAURANT_RECOVERY.SEED_DEMO()", "DROP PROCEDURE", "./02_analytics.sql", "./04_semantics.sql", "COPY FILES", "./05_agent.sql", "./03_reader.sql"]
        positions = [text.index(stage) for stage in stages]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('EXECUTE AS CALLER', text)
        self.assertNotIn('expected_answers', text)
        self.assertEqual(text.count("FILES = ('SKILL.md')"), 2)
        self.assertNotIn('PUT ', text)

    def test_teardown_preserves_shared_infrastructure(self):
        text = (ROOT / 'teardown_all.sql').read_text()
        self.assertNotIn('DROP DATABASE', text)
        self.assertNotIn('DROP GIT REPOSITORY', text)
        self.assertNotIn('DROP API INTEGRATION', text)
        self.assertNotIn('CASCADE', text)
        self.assertIn('RESTRICT', text)
        self.assertIn('Run All', text)
        self.assertNotIn('RR_CONFIRM', text)
        self.assertNotIn('RR_EXPECTED_ACCOUNT', text)

    def test_sql_is_the_only_definition_source(self):
        text = (ROOT / 'sql/04_semantics.sql').read_text()
        specs = [json.loads(value) for value in re.findall(r'\$\$\n(.*?)\n\$\$', text, re.DOTALL)]
        self.assertEqual(len(specs), 3)
        self.assertEqual(sum(len(spec['verified_queries']) for spec in specs), 8)
        self.assertFalse(list((ROOT / 'cortex_project').glob('*.yaml')))
        self.assertFalse((ROOT / 'tools/build_specs.py').exists())
        agent_sql = (ROOT / 'sql/05_agent.sql').read_text()
        agent = json.loads(re.search(r'\$\$\n(.*?)\n\$\$', agent_sql, re.DOTALL)[1])
        self.assertEqual(len(agent['skills']), 2)
        self.assertEqual(len(agent['tools']), 3)
        self.assertTrue(all('/skills/{{ revision }}/' in skill['source']['path'] for skill in agent['skills']))
        self.assertIn('COPY GRANTS', agent_sql)

    def run_seed(self, failure=False):
        session = MagicMock()
        commands = []
        schema = types.SimpleNamespace(fields=[types.SimpleNamespace(name='RELEASE_ID', datatype=object())])
        session.table.return_value.schema = schema

        def query(statement, **kwargs):
            commands.append(statement)
            result = MagicMock()
            if statement.startswith('SHOW'):
                result.collect.return_value = []
            elif 'WHERE RELEASE_ID' in statement:
                result.collect.return_value = [[0]]
            elif statement.startswith('SELECT COUNT'):
                result.collect.return_value = [[1]]
            elif failure and statement.startswith('INSERT'):
                result.collect.side_effect = RuntimeError('injected insert failure')
            return result

        session.sql.side_effect = query
        module = types.ModuleType('snowflake.snowpark.types')
        module.DateType = type('DateType', (), {})
        module.DecimalType = type('DecimalType', (), {})
        fixture = {'ROSTER': [{'RELEASE_ID': native_runtime.RELEASE}]}
        with patch.dict(sys.modules, {'snowflake.snowpark.types': module}), \
             patch.object(native_runtime, 'observations', return_value=fixture), \
             patch.object(native_runtime, 'validate'), \
             patch.object(native_runtime, 'FIELDS', {'ROSTER': ['RELEASE_ID']}):
            if failure:
                with self.assertRaisesRegex(RuntimeError, 'injected'):
                    native_runtime.seed(session)
            else:
                native_runtime.seed(session)
        return session, commands

    def test_seed_transaction_and_temporary_staging(self):
        session, commands = self.run_seed()
        self.assertLess(commands.index('BEGIN TRANSACTION'), next(index for index, value in enumerate(commands) if value.startswith('DELETE')))
        self.assertIn('COMMIT', commands)
        self.assertNotIn('ROLLBACK', commands)
        self.assertEqual(session.create_dataframe.return_value.write.mode.return_value.save_as_table.call_args.kwargs['table_type'], 'temporary')
        self.assertTrue(commands[-1].startswith('DROP TABLE IF EXISTS'))

    def test_seed_failure_rolls_back_and_cleans_up(self):
        _, commands = self.run_seed(failure=True)
        self.assertIn('ROLLBACK', commands)
        self.assertNotIn('COMMIT', commands)
        self.assertTrue(commands[-1].startswith('DROP TABLE IF EXISTS'))


class PublicVocabularyTests(unittest.TestCase):
    def test_no_tracked_file_names_a_snowflake_internal_system(self):
        # This repository is public. It previously shipped a deploy-time guard
        # that refused to run in an internal Snowflake account, which meant a
        # synthetic restaurant demo named an internal system in a file anyone
        # could read. The guard bought nothing -- safety comes from the demo's
        # own object namespace and teardown -- so the words must simply
        # never reappear. The terms live only in check_public_source.py, which
        # is exempt from its own scan and imported here rather than restated.
        import check_public_source

        tracked = subprocess.run(['git', 'ls-files', '-z'], cwd=ROOT, check=True,
                                 capture_output=True, text=True).stdout.split('\0')
        offenders = []
        for name in filter(None, tracked):
            if name == check_public_source.SELF_EXEMPT:
                continue
            path = ROOT / name
            if not path.is_file() or path.suffix not in check_public_source.TEXT_SUFFIXES:
                continue
            for line_number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                if check_public_source.INTERNAL_TERMS.search(line):
                    offenders.append(f'{name}:{line_number}')
        self.assertEqual(offenders, [])


if __name__ == '__main__':
    unittest.main()