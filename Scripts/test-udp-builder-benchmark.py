#!/usr/bin/env python3
"""Behavioral regression checks for benchmark acceptance inputs."""
import os
import sys
sys.dont_write_bytecode = True
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
specification = importlib.util.spec_from_file_location('udp_benchmark', ROOT / 'Scripts/udp-builder-benchmark.py')
harness = importlib.util.module_from_spec(specification)
specification.loader.exec_module(harness)


class AcceptanceTests(unittest.TestCase):
    def rejected_before_build(self, arguments, diagnostic):
        with tempfile.TemporaryDirectory() as scratch:
            swift = Path(scratch) / 'swift'
            swift.write_text('#!/bin/sh\necho UNEXPECTED_BUILD >&2\nexit 73\n')
            swift.chmod(0o755)
            environment = dict(os.environ, PATH=scratch + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', str(ROOT / 'Scripts/benchmark-udp-builder.sh'),
                                     '--output', str(Path(scratch) / 'result.json'), *arguments],
                                    cwd=ROOT, env=environment, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(diagnostic, result.stderr)
            self.assertNotIn('UNEXPECTED_BUILD', result.stderr)

    def test_missing_history_rejects_before_build(self):
        self.rejected_before_build(['--baseline', '0' * 40, '--allow-dirty'], 'fetch')

    def test_dirty_acceptance_rejects_before_build(self):
        # A temporary untracked file makes this reproducible on clean commits.
        with tempfile.NamedTemporaryFile(dir=ROOT, prefix='.udp-dirty-test-'):
            self.rejected_before_build([], 'dirty')

    def test_invalid_baseline_rejects_before_build(self):
        self.rejected_before_build(['--baseline', 'HEAD'], 'full 40-character')

    def test_provenance_missing_and_malformed_fields_reject(self):
        valid = dict(baseline_sha='a' * 40, candidate_sha='b' * 40, dirty=False,
                     baseline_source_sha256='c' * 64, benchmark_source_sha256='d' * 64,
                     executable_sha256='e' * 64, fixture_sha256='f' * 64,
                     swift_version='Swift test', os='test', architecture='test', build_flags=['-O'])
        harness.validate_provenance(valid, False)
        for field in valid:
            with self.subTest(field=field):
                missing = dict(valid)
                del missing[field]
                with self.assertRaises(ValueError):
                    harness.validate_provenance(missing, False)
        for field in ('candidate_sha', 'baseline_sha', 'fixture_sha256', 'executable_sha256'):
            malformed = dict(valid, **{field: 'not-a-digest'})
            with self.assertRaises(ValueError):
                harness.validate_provenance(malformed, False)
        for field in ('candidate_sha', 'fixture_sha256', 'swift_version', 'os', 'architecture'):
            with self.subTest(malformed_type=field):
                with self.assertRaises(ValueError):
                    harness.validate_provenance(dict(valid, **{field: 42}), False)
        with self.assertRaises(ValueError):
            harness.validate_provenance(dict(valid, build_flags='-O'), False)
        with self.assertRaises(ValueError):
            harness.validate_provenance(dict(valid, dirty='false'), False)
        with self.assertRaises(ValueError):
            harness.validate_provenance(dict(valid, dirty=True), False)
        harness.validate_provenance(dict(valid, dirty=True), True)

    def test_correctness_artifact(self):
        artifact = os.environ.get('FORGEBASE_BENCHMARK_TEST_RESULT')
        if not artifact:
            self.skipTest('set FORGEBASE_BENCHMARK_TEST_RESULT to a fresh native/self-test result')
        document = json.loads(Path(artifact).read_text())
        harness.validate_provenance(document['provenance'], True)
        self.assertEqual(document['schema_version'], 1)
        result = document['result']
        self.assertTrue(result['oracle_passed'])
        self.assertEqual(result['fixture_sha256'], '34098b7abdc7efaae5908f31cc4c5bddddffc87ceb39ddb32b5ea41a56db5e91')
        self.assertEqual(len(result['workloads']), 20)
        self.assertEqual({row['payload_size'] for row in result['workloads']}, {0, 64, 1472, 4096, 65507})
        self.assertEqual({row['path'] for row in result['workloads']}, {'data', 'borrowed', 'nested_slice', 'legacy_fallback'})
        for row in result['observations']:
            self.assertEqual(row['scoped_borrow_override_calls'], 3 if row['path'] in ('borrowed', 'nested_slice') else 0)
            self.assertEqual(row['materialize_calls'], 3 if row['path'] == 'legacy_fallback' else 0)
            self.assertEqual(row['owned_output_payload_bytes'], row['payload_size'])
        for row in result['workloads']:
            if result['timing_status'] == 'not_run':
                self.assertEqual(row['rounds'], [])
                self.assertEqual(row['iterations'], 0)
            else:
                self.assertEqual([round['order'] for round in row['rounds']][:2], ['AB', 'BA'])
                self.assertTrue(all(round['baseline_batch_ns'] > 0 and round['candidate_batch_ns'] > 0 for round in row['rounds']))


if __name__ == '__main__':
    result = unittest.TextTestRunner().run(unittest.TestLoader().loadTestsFromTestCase(AcceptanceTests))
    sys.exit(0 if result.wasSuccessful() else 1)
