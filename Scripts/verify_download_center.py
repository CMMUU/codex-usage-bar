#!/usr/bin/env python3
"""Verify the published center's exact version and signed release bytes."""
import argparse
import hashlib
import json
import pathlib
import re
import time
import urllib.error
import urllib.request

CENTER = 'https://downloads.cmmuu.com'
FILES = 'https://files.cmmuu.com'
PROJECT = 'codex-usage-bar'

class PreserveHeadRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        redirected = super().redirect_request(request, response, code, message, headers, new_url)
        if redirected is not None and request.get_method() == 'HEAD':
            redirected.method = 'HEAD'
        return redirected

def get(url, limit=256 * 1024, method='GET', headers=None):
    request = urllib.request.Request(url, method=method, headers=headers or {})
    opener = urllib.request.build_opener(PreserveHeadRedirects())
    with opener.open(request, timeout=25) as response:
        body = response.read(limit + 1)
        if len(body) > limit:
            raise ValueError('Response exceeds expected size')
        return body, response.headers

def validate_catalog(data, tag, size, sha256):
    name = f'Codex-Usage-Bar-{tag}-universal.dmg'
    assets = data.get('assets', {})
    if data.get('schemaVersion') != 1 or data.get('project') != PROJECT or data.get('version') != tag or set(assets) != {'macos-universal'}:
        raise ValueError('Download center version is not ready')
    asset = assets['macos-universal']
    if (asset.get('filename'), asset.get('size'), asset.get('sha256'), asset.get('channel'), asset.get('hkAvailable')) != (name, size, sha256, 'hk', True):
        raise ValueError('Installer identity differs from the published build')
    if asset.get('downloadUrl') != f'{CENTER}/download/{PROJECT}/latest/macos-universal' or asset.get('fileUrl') != f'{FILES}/releases/{PROJECT}/{tag}/{name}':
        raise ValueError('Unexpected download origin or file URL')
    return asset

def verify(tag, dist):
    name = f'Codex-Usage-Bar-{tag}-universal.dmg'
    dmg = dist / name
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    raw, _ = get(f'{CENTER}/api/projects/{PROJECT}/releases/latest')
    asset = validate_catalog(json.loads(raw), tag, dmg.stat().st_size, digest)
    _, headers = get(asset['downloadUrl'], method='HEAD')
    if int(headers.get('Content-Length', 0)) != asset['size']:
        raise ValueError('HEAD size mismatch')
    body, headers = get(asset['fileUrl'], limit=64, headers={'Range': 'bytes=0-63'})
    with dmg.open('rb') as stream:
        if body != stream.read(64) or headers.get('Content-Range') != f"bytes 0-63/{asset['size']}":
            raise ValueError('Range response mismatch')
    for filename in (name, name + '.sha256', 'appcast.xml', 'appcast-center.xml'):
        local = (dist / filename).read_bytes()
        remote, _ = get(f'{FILES}/releases/{PROJECT}/{tag}/{filename}', limit=len(local))
        if hashlib.sha256(remote).digest() != hashlib.sha256(local).digest():
            raise ValueError('Archived release asset differs: ' + filename)
    feed, _ = get(f'{CENTER}/api/releases/{PROJECT}/appcast.xml')
    if feed != (dist / 'appcast-center.xml').read_bytes():
        raise ValueError('Update feed is not the original signed center feed')
    print('Download center verified:', tag, 'installer, four original assets, HEAD/Range, signed feed')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--dist', type=pathlib.Path, default=pathlib.Path('dist'))
    parser.add_argument('--wait-seconds', type=int, default=0)
    args = parser.parse_args()
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', args.version) or not 0 <= args.wait_seconds <= 600:
        parser.error('Expected a formal version and bounded wait of 0–600 seconds')
    deadline = time.monotonic() + args.wait_seconds
    while True:
        try:
            verify('v' + args.version, args.dist)
            return
        except (ValueError, OSError, urllib.error.URLError) as error:
            if time.monotonic() >= deadline:
                raise
            print('Waiting for verified center sync:', type(error).__name__, flush=True)
            time.sleep(min(15, max(0, deadline - time.monotonic())))

if __name__ == '__main__':
    main()
