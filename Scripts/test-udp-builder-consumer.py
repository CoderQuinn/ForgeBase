#!/usr/bin/env python3
"""Resolve the public HTTPS Git dependency at exact revisions in clean consumers."""
import argparse
import json
import re
import subprocess  # nosec B404 - process argv is audited at each shell=False call below.
import tempfile
from pathlib import Path

URL = 'https://github.com/CoderQuinn/ForgeBase.git'
OLD = 'd1f6656ef8f674277484ca54237a0eeb40c8b3c3'
SMOKE = '''import Foundation
import Network
import ForgeBase
import ForgeBaseC
let payload = Data([1, 2, 3, 4])
let backing = Data([99, 98, 1, 2, 3, 4, 97]).dropFirst()
let window: any FBPacketBuffer = FBDataPacketBuffer(backing).slice(from: 1, length: 4)!
precondition(window.withUnsafeReadableBytes { Data($0) } == payload)
let packet = try FBUDPIPPacketBuilder.buildUDPIPv4(srcIP: IPv4Address("192.0.2.1")!, dstIP: IPv4Address("198.51.100.2")!, srcPort: 1234, dstPort: 443, payloadBuffer: window)
let ip = FBIPPacketView(buffer: FBDataPacketBuffer(packet))!
let udp = FBUDPView(ip: ip)!
precondition(packet.count == 32 && udp.srcPort == 1234 && udp.dstPort == 443)
precondition(udp.payload.materialize() == payload)
var writer = FBPacketBufferWriter()
try writer.writeDNSName("example.test")
precondition(writer.data == Data([7]) + Data("example".utf8) + Data([4]) + Data("test".utf8) + Data([0]))
do {
    _ = try FBUDPIPPacketBuilder.buildUDPIPv4(srcIP: IPv4Address("192.0.2.1")!, dstIP: IPv4Address("198.51.100.2")!, srcPort: 1234, dstPort: 443, payloadBuffer: FBDataPacketBuffer(Data(count: 65508)))
    fatalError("accepted oversized payload")
} catch FBUDPIPPacketBuilderError.payloadTooLarge(let actual, let maximum) {
    precondition(actual == 65508 && maximum == 65507)
}
print("borrowed consumer passed")
'''


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def consumer(revision, root, expected_success):
    root.mkdir()
    source = root / 'Sources/Probe'
    source.mkdir(parents=True)
    (source / 'main.swift').write_text(SMOKE)
    (root / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Probe", platforms: [.macOS(.v11)], dependencies: [.package(url: "''' + URL + '''", revision: "''' + revision + '''")], targets: [.executableTarget(name: "Probe", dependencies: [.product(name: "ForgeBase", package: "ForgeBase"), .product(name: "ForgeBaseC", package: "ForgeBase")])])
''')
    # All tool arguments are constants; the private consumer directory is cwd data.
    completed = subprocess.run(['swift', 'run', '-c', 'release', '-Xswiftc', '-strict-concurrency=complete', '-Xswiftc', '-warnings-as-errors', 'Probe'], shell=False, cwd=root, text=True, capture_output=True)  # nosec B603 - fixed Swift command argv.
    pins = json.loads((root / 'Package.resolved').read_text())['pins']
    check(len(pins) == 1 and pins[0]['state']['revision'] == revision, 'resolved revision mismatch')
    check(pins[0]['location'] == URL, 'consumer used a substituted dependency URL')
    checkout = root / '.build/checkouts/ForgeBase'
    # Both git probes have constant argv and inspect only this consumer checkout.
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], shell=False, cwd=checkout, text=True).strip()  # nosec B603 - fixed git inspection argv.
    check(actual == revision, 'checkout revision mismatch')
    check(not subprocess.check_output(['git', 'status', '--porcelain'], shell=False, cwd=checkout), 'dirty dependency checkout')  # nosec B603 - fixed git inspection argv.
    if expected_success:
        check(completed.returncode == 0, completed.stderr)
        check(completed.stdout.strip() == 'borrowed consumer passed', completed.stdout)
    else:
        check(completed.returncode != 0, 'old version unexpectedly supports new APIs')
        check('withUnsafeReadableBytes' in completed.stderr and 'payloadBuffer' in completed.stderr, completed.stderr)
    return dict(revision=revision, resolved_revision=pins[0]['state']['revision'], checkout_revision=actual,
                clean=True, borrowed_api='passed' if expected_success else 'compile_rejected_as_expected')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', options.revision):
        parser.error('revision must be an exact 40-character SHA')
    with tempfile.TemporaryDirectory(prefix='forgebase-git-consumer-') as directory:
        root = Path(directory)
        result = dict(url=URL, candidate=consumer(options.revision, root / 'candidate', True),
                      old_v0_3_0=consumer(OLD, root / 'old', False))
        options.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('Exact HTTPS consumer and old-version rejection passed.')


if __name__ == '__main__':
    main()
