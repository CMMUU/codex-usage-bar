import copy
import importlib.util
import pathlib
import os
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('verify_signing', pathlib.Path(__file__).parents[1] / 'verify_signing.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SigningChecks(unittest.TestCase):
    def setUp(self):
        self.team = 'TESTTEAM12'
        self.group = self.team + '.io.cmmuu.codex-usage-bar'
        self.info = {'CodexUsageSharedStorageEnabled': True, 'CodexUsageAppGroupIdentifier': self.group}
        self.entitlements = {'com.apple.security.application-groups': [self.group], 'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True}

    def verify(self, app_info=None, widget_entitlements=None):
        module.validate_shared_group(app_info or self.info, self.info, self.entitlements, widget_entitlements or self.entitlements, self.team)

    def test_valid_authorized_group(self):
        self.verify()

    def test_unprovisioned_legacy_group_rejected(self):
        info = dict(self.info, CodexUsageAppGroupIdentifier='group.io.cmmuu.codex-usage-bar')
        with self.assertRaises(ValueError):
            self.verify(app_info=info)

    def test_other_team_rejected(self):
        entitlements = copy.deepcopy(self.entitlements)
        entitlements['com.apple.security.application-groups'] = ['OTHERTEAM1.io.cmmuu.codex-usage-bar']
        with self.assertRaises(ValueError):
            self.verify(widget_entitlements=entitlements)

    def test_disabled_release_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(app_info=dict(self.info, CodexUsageSharedStorageEnabled=False))

    def test_widget_debugging_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(widget_entitlements=dict(self.entitlements, **{'com.apple.security.get-task-allow': True}))

    def test_release_rejects_adhoc_before_build(self):
        env = dict(os.environ, APPLE_TEAM_ID=self.team, CODE_SIGN_IDENTITY='-')
        script = pathlib.Path(__file__).parents[1] / 'release_package.sh'
        result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Official releases cannot use ad-hoc signing', result.stderr)
