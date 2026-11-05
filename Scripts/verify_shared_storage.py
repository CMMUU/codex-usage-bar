#!/usr/bin/env python3
"""Exercise real macOS App Group access in separately signed sandboxed processes.

This checks OS authorization, not WidgetKit rendering or timeline scheduling.
Only a unique probe file is created in the real shared group; usage is untouched.
"""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile
import uuid

from verify_signing import verify


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=pathlib.Path, required=True)
    parser.add_argument('--team', required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    verify(args.app, args.team)
    args.output.mkdir(parents=True, exist_ok=True)
    group = args.team + '.io.cmmuu.codex-usage-bar'
    source = pathlib.Path(__file__).with_name('shared_storage_probe.swift')
    with tempfile.TemporaryDirectory(prefix='shared-storage-', dir=args.output) as temporary:
        work = pathlib.Path(temporary)
        binary = work / 'probe'
        subprocess.run(['xcrun', 'swiftc', str(source), '-o', str(binary)], check=True)
        executables = []
        for name, sandboxed in (('AppProbe', False), ('WidgetProbe', True)):
            bundle = work / (name + '.app')
            contents = bundle / 'Contents'
            executable = contents / 'MacOS' / name
            executable.parent.mkdir(parents=True)
            executable.write_bytes(binary.read_bytes())
            executable.chmod(0o755)
            info = {'CFBundleIdentifier': 'io.cmmuu.codex-usage-bar.probe.' + name.lower(),
                    'CFBundleExecutable': name, 'CFBundlePackageType': 'APPL',
                    'CFBundleVersion': '1'}
            (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
            entitlements = {'com.apple.security.application-groups': [group]}
            if sandboxed:
                entitlements['com.apple.security.app-sandbox'] = True
            entitlement_file = work / (name + '.entitlements')
            entitlement_file.write_bytes(plistlib.dumps(entitlements))
            subprocess.run(['codesign', '--force', '--sign', args.identity, '--options', 'runtime',
                            '--timestamp', '--entitlements', str(entitlement_file), str(bundle)], check=True)
            executables.append(executable)
        probe_name = 'codex-sync-probe-' + str(uuid.uuid4()) + '.json'
        for executable, operation in ((executables[0], 'write'), (executables[1], 'read-and-ack'),
                                      (executables[0], 'verify-and-remove')):
            subprocess.run([str(executable), group, probe_name, operation], check=True, timeout=20)
    print('Verified real macOS shared writes, sandboxed widget reads and acknowledgement')


if __name__ == '__main__':
    main()
