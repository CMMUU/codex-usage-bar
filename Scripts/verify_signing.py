#!/usr/bin/env python3
"""Validate the actual signing identity and shared capability of a packaged app."""
import argparse
import pathlib
import plistlib
import re
import subprocess


def validate_shared_group(app_info, widget_info, app_entitlements, widget_entitlements, team):
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('A valid expected Apple Team ID is required')
    group = team + '.io.cmmuu.codex-usage-bar'
    for info, entitlements in ((app_info, app_entitlements), (widget_info, widget_entitlements)):
        if info.get('CodexUsageSharedStorageEnabled') is not True:
            raise ValueError('Shared storage is disabled in a release bundle')
        if info.get('CodexUsageAppGroupIdentifier') != group:
            raise ValueError('Bundle App Group does not belong to the expected team')
        if entitlements.get('com.apple.security.application-groups') != [group]:
            raise ValueError('Signed App Group entitlement differs from bundle configuration')
        if entitlements.get('com.apple.security.get-task-allow'):
            raise ValueError('Release bundle allows debugging')
    if widget_entitlements.get('com.apple.security.app-sandbox') is not True:
        raise ValueError('Widget is not sandboxed')
    if widget_entitlements.get('com.apple.security.network.client') is not True:
        raise ValueError('Widget cannot use the loopback fallback')


def verify(app, team, version=None, notarized=False):
    widget = app / 'Contents/PlugIns/CodexUsageWidget.appex'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    infos, entitlements = [], []
    for bundle in (app, widget):
        info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
        infos.append(info)
        if version and info.get('CFBundleShortVersionString') != version:
            raise ValueError('Prepared installer version differs from release tag')
        result = subprocess.run(['codesign', '-dv', '--verbose=4', str(bundle)], capture_output=True, text=True, check=True)
        details = result.stderr
        if 'Authority=Developer ID Application:' not in details or f'TeamIdentifier={team}\n' not in details:
            raise ValueError('Release requires the expected Developer ID Application identity')
        if '(runtime)' not in details:
            raise ValueError('Hardened Runtime is missing')
        signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True, check=True)
        entitlements.append(plistlib.loads(signed.stdout))
    validate_shared_group(*infos, *entitlements, team)
    if infos[0].get('CFBundleIdentifier') != 'io.cmmuu.codex-usage-bar' or infos[1].get('CFBundleIdentifier') != 'io.cmmuu.codex-usage-bar.widget':
        raise ValueError('Prepared installer bundle identity is not this application')
    if infos[0].get('CFBundleVersion') != infos[1].get('CFBundleVersion'):
        raise ValueError('App and widget build numbers differ')
    if notarized:
        subprocess.run(['xcrun', 'stapler', 'validate', str(app)], check=True)
    print('Verified Developer ID team, Hardened Runtime, app/widget identity and App Group authorization configuration')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=pathlib.Path, required=True)
    parser.add_argument('--team', required=True)
    parser.add_argument('--version')
    parser.add_argument('--notarized', action='store_true')
    args = parser.parse_args()
    verify(args.app, args.team, args.version, args.notarized)
