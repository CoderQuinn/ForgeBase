#!/usr/bin/env python3
"""Build the native benchmark with exact source provenance. No timing by default."""
import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'd5a75c766871436619b8fb431567b7d7ebf2d839'
BUILDER = 'Sources/ForgeBase/Net/Packets/UDPIPPacketBuilder.swift'
BENCHMARK = 'Benchmarks/UDPIPPacketBuilder/main.swift'
FLAGS = ['-O', '-strict-concurrency=complete', '-warnings-as-errors']


def run(arguments, cwd=ROOT):
    return subprocess.check_output(arguments, cwd=cwd, stderr=subprocess.PIPE).decode().strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_provenance(provenance, allow_dirty):
    for field in ('baseline_sha', 'candidate_sha'):
        if not isinstance(provenance.get(field), str) or not re.fullmatch(r'[0-9a-f]{40}', provenance[field]):
            raise ValueError('missing or malformed ' + field)
    for field in ('baseline_source_sha256', 'benchmark_source_sha256', 'executable_sha256', 'fixture_sha256'):
        if not isinstance(provenance.get(field), str) or not re.fullmatch(r'[0-9a-f]{64}', provenance[field]):
            raise ValueError('missing or malformed ' + field)
    if type(provenance.get('dirty')) is not bool:
        raise ValueError('missing or malformed dirty flag')
    if provenance['dirty'] and not allow_dirty:
        raise ValueError('dirty checkout: commit changes or use --allow-dirty for diagnostic evidence')
    for field in ('swift_version', 'os', 'architecture'):
        if not isinstance(provenance.get(field), str) or not provenance[field]:
            raise ValueError('missing or malformed ' + field)
    flags = provenance.get('build_flags')
    if not isinstance(flags, list) or not flags or not all(isinstance(flag, str) and flag for flag in flags):
        raise ValueError('missing or malformed build_flags')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--baseline', default=BASELINE)
    parser.add_argument('--allow-dirty', action='store_true')
    parser.add_argument('--measure', action='store_true')
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--profile-check', type=Path, help='instrumented correctness coverage directory; not performance evidence')
    options = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', options.baseline):
        raise ValueError('baseline must be a full 40-character commit SHA')
    try:
        baseline_sha = run(['git', 'rev-parse', '--verify', options.baseline + '^{commit}'])
        source = subprocess.check_output(['git', 'show', baseline_sha + ':' + BUILDER], cwd=ROOT, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        raise ValueError('historical builder unavailable; fetch the exact baseline commit with full history before running') from error
    candidate_sha = run(['git', 'rev-parse', '--verify', 'HEAD'])
    worktree_status = run(['git', 'status', '--porcelain', '--untracked-files=all'])
    dirty = bool(worktree_status)
    benchmark_source = (ROOT / BENCHMARK).read_bytes()
    if dirty and not options.allow_dirty:
        raise ValueError('dirty checkout: commit changes or use --allow-dirty for diagnostic evidence')
    fixtures = b''.join(bytes(index % 256 for index in range(size)) for size in (0, 64, 1472, 4096, 65507))
    with tempfile.TemporaryDirectory(prefix='forge-udp-benchmark-') as directory:
        scratch = Path(directory)
        baseline_source = scratch / 'Baseline.swift'
        baseline_source.write_bytes(source.replace(b'FBUDPIPPacketBuilder', b'BaselineUDPIPPacketBuilder'))
        print('Building native Release correctness harness...', file=sys.stderr)
        run(['swift', 'build', '-c', 'release', '-Xswiftc', '-strict-concurrency=complete', '-Xswiftc', '-warnings-as-errors'])
        build = Path(run(['swift', 'build', '-c', 'release', '--show-bin-path']))
        run(['swiftc', *FLAGS, '-parse-as-library', '-module-name', 'Baseline', '-emit-module',
             '-emit-module-path', str(scratch / 'Baseline.swiftmodule'), '-emit-object', str(baseline_source),
             '-o', str(scratch / 'Baseline.o')])
        executable = scratch / 'benchmark'
        flags = FLAGS + (['-profile-generate', '-profile-coverage-mapping'] if options.profile_check else [])
        run(['swiftc', *flags, '-parse-as-library', '-I', str(scratch), '-I', str(build / 'Modules'),
             '-I', str(build / 'ForgeBaseC.build'), str(ROOT / BENCHMARK), str(scratch / 'Baseline.o'),
             *map(str, sorted((build / 'ForgeBase.build').glob('*.o'))),
             str(build / 'ForgeBaseC.build/include/forge_base.c.o'), '-o', str(executable)])
        arguments = [str(executable)]
        for option in ('measure', 'smoke', 'self_test'):
            if getattr(options, option):
                arguments.append('--' + option.replace('_', '-'))
        if options.profile_check:
            options.profile_check.mkdir(parents=True, exist_ok=True)
            executable_copy = options.profile_check / 'benchmark'
            executable_copy.write_bytes(executable.read_bytes())
            arguments.append('--profile-check')
            environment = dict(os.environ, LLVM_PROFILE_FILE=str(options.profile_check / 'benchmark.profraw'))
            result = json.loads(subprocess.check_output(arguments, env=environment))
        else:
            result = json.loads(run(arguments))
        if run(['git', 'rev-parse', 'HEAD']) != candidate_sha or run(['git', 'status', '--porcelain', '--untracked-files=all']) != worktree_status or (ROOT / BENCHMARK).read_bytes() != benchmark_source:
            raise ValueError('checkout changed during benchmark; discard this run')
        provenance = dict(baseline_sha=baseline_sha, candidate_sha=candidate_sha, dirty=dirty,
                          baseline_source_sha256=digest(source), benchmark_source_sha256=digest(benchmark_source),
                          executable_sha256=digest(executable.read_bytes()), fixture_sha256=digest(fixtures),
                          swift_version=run(['swift', '--version']), os=platform.platform(), architecture=platform.machine(), build_flags=flags)
        validate_provenance(provenance, options.allow_dirty)
        if result['fixture_sha256'] != provenance['fixture_sha256'] or result['oracle_passed'] is not True:
            raise ValueError('benchmark oracle/fixture validation failed')
        document = dict(schema_version=1, provenance=provenance,
                        qualification='diagnostic_dirty' if dirty else ('instrumented_correctness' if options.profile_check else ('native_measurement' if options.measure else 'correctness_only')), result=result)
        options.output.write_text(json.dumps(document, indent=2, sort_keys=True) + '\n')
    print('Wrote ' + str(options.output), file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        detail = error.stderr.decode() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print('error: ' + detail, file=sys.stderr)
        sys.exit(1)
