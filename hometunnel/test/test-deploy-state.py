"""Isolated backend deployment-state regression tests (no router/network calls)."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/hometunnel/hometunnel.sh'


class DeploymentState(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR') or None)
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        shell_root = self.root.as_posix()
        for folder in ('etc', 'run', 'share', 'bin'):
            (self.root / folder).mkdir()
        (self.root / 'etc/ctl.key').write_text('test-key')
        (self.root / 'etc/oauth.json').write_text('{"account_id":"acct"}')
        self.log = self.root / 'actions'
        self.env = dict(os.environ, PATH=(self.root / 'bin').as_posix() + ':' + os.environ['PATH'],
                        TEST_ROOT=shell_root, TEST_REMOTE='worker:hometunnel-ctl', TEST_HEALTH='ok')
        uci = self.root / 'bin/uci'
        uci.write_text('''#!/bin/sh
case "$*" in
  '-q get hometunnel.global.domain') echo example.test ;;
  '-q get hometunnel.global.ctl_hostname') cat "$TEST_ROOT/host" 2>/dev/null || echo ctl ;;
  '-q get hometunnel.global.tunnel_id') echo tunnel-id ;;
  'set hometunnel.global.ctl_hostname='*) printf '%s' "${4#*=}" > "$TEST_ROOT/host" ;;
  *) : ;;
esac
''')
        uci.chmod(0o755)
        src = SOURCE.read_text()
        for name, target in (('SHARE', 'share'), ('RUNDIR', 'run'), ('ETC', 'etc')):
            src = src.replace(f'{name}=/{"usr/share/hometunnel" if name == "SHARE" else "var/run/hometunnel" if name == "RUNDIR" else "etc/hometunnel"}', f'{name}={shell_root}/{target}', 1)
        # Replace only external boundaries; exercise the real dispatch/state logic.
        hook = '''
oauth_valid_token() { echo token; }
cf_zone_id() { echo zone; }
ctl_domain_check() { echo "$TEST_REMOTE"; }
upload_worker() { echo upload >> "$TEST_ROOT/actions"; }
cmd_route() { echo route >> "$TEST_ROOT/actions"; [ "${TEST_ROUTE_FAIL:-0}" = 0 ]; }
cmd_regen() { echo regen >> "$TEST_ROOT/actions"; [ "${TEST_REGEN_FAIL:-0}" = 0 ] || return 1; [ "${TEST_NO_CONFIG:-0}" = 1 ] || echo generated > "$TEST_ROOT/etc/config.yml"; }
cmd_apply_mode() { echo apply >> "$TEST_ROOT/actions"; [ "${TEST_APPLY_FAIL:-0}" = 0 ]; }
check_dns_all() { echo "${TEST_DNS:-ok}"; }
verify_worker_http() { [ "$TEST_HEALTH" = ok ] || die 'health timeout'; }
cmd_verify() { echo verify >> "$TEST_ROOT/actions"; [ "$TEST_HEALTH" = ok ] || die '/cmd authentication failed'; }
curl() { echo bind >> "$TEST_ROOT/actions"; echo '{"success":true}'; }
write_ttl_snapshot() { echo snapshot >> "$TEST_ROOT/actions"; }
'''
        src = src.replace('case "${1:-}" in\n\tjob)', hook + '\ncase "${1:-}" in\n\tjob)')
        self.script = self.root / 'backend.sh'
        self.script.write_text(src)

    def run_cmd(self, *args, **env):
        return subprocess.run(['sh', self.script.as_posix(), *args], capture_output=True, text=True,
                              env={**self.env, **env})

    def actions(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_bound_state_is_pending_and_deploy_timeout_is_not_failure(self):
        r = self.run_cmd('deploy', TEST_HEALTH='fail')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('pending', self.run_cmd('deploy-state').stdout)
        self.assertFalse((self.root / 'run/worker-deployed').exists())

    def test_verified_state_then_ready_only_after_publish(self):
        (self.root / 'etc/worker-bound').write_bytes(b'ctl.example.test\n')
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        self.assertIn('verified', self.run_cmd('deploy-state').stdout)
        self.assertEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertIn('ready', self.run_cmd('deploy-state').stdout)

    def test_binding_mismatch_or_remote_uncertainty_never_looks_ready(self):
        (self.root / 'etc/worker-bound').write_bytes(b'other.example.test\n')
        self.assertIn('error', self.run_cmd('deploy-state').stdout)
        self.assertNotEqual(self.run_cmd('set', 'ctl_hostname', 'another').returncode, 0)

    def test_finish_fails_if_dns_readback_missing(self):
        (self.root / 'etc/worker-bound').write_bytes(b'ctl.example.test\n')
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        self.assertNotEqual(self.run_cmd('deploy-finish', TEST_DNS='missing:2').returncode, 0)
        self.assertFalse((self.root / 'run/worker-deployed').exists())

    def test_completion_survives_restart_without_tmpfs_marks(self):
        (self.root / 'etc/worker-bound').write_bytes(b'ctl.example.test\n')
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        self.assertEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertEqual(self.run_cmd('deploy-complete').returncode, 0)
        for name in ('worker-verified', 'worker-deployed', 'dns-routed'):
            (self.root / 'run' / name).unlink(missing_ok=True)
        self.assertIn('complete', self.run_cmd('deploy-state').stdout)

    def test_complete_state_is_local_and_skips_remote_api(self):
        host = b'ctl.example.test\n'
        for name in ('worker-bound', 'worker-health', 'worker-ready', 'worker-complete'):
            (self.root / 'etc' / name).write_bytes(host)
        (self.root / 'etc/config.yml').write_bytes(b'generated\n')
        r = self.run_cmd('deploy-state', TEST_REMOTE='error:must-not-call')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('complete', r.stdout)
        self.assertEqual(self.actions(), [])

    def test_failed_mode_apply_cannot_complete(self):
        (self.root / 'etc/worker-bound').write_bytes(b'ctl.example.test\n')
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        self.assertEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertNotEqual(self.run_cmd('deploy-complete', TEST_APPLY_FAIL='1').returncode, 0)
        self.assertNotIn('complete', self.run_cmd('deploy-state').stdout)

    def test_binding_survives_health_timeout_and_blocks_hostname_change(self):
        r = self.run_cmd('deploy', TEST_HEALTH='fail')
        self.assertEqual(r.returncode, 0)
        self.assertTrue((self.root / 'etc/worker-bound').exists())
        self.assertEqual(self.actions().count('upload'), 1)
        self.assertNotEqual(self.run_cmd('set', 'ctl_hostname', 'other').returncode, 0)
        self.assertFalse((self.root / 'host').exists())

    def test_remote_binding_recovery_does_not_upload_and_finishes_after_verify(self):
        r = self.run_cmd('deploy-state', TEST_REMOTE='worker:hometunnel-ctl')
        self.assertIn('pending', r.stdout)
        self.assertTrue((self.root / 'etc/worker-bound').exists())
        self.assertEqual(self.actions(), [])
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        self.assertEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertTrue((self.root / 'run/worker-deployed').exists())
        self.assertEqual(self.actions(), ['verify', 'route', 'regen'])

    def test_finish_requires_verification_and_both_publish_steps(self):
        (self.root / 'etc/worker-bound').write_bytes(b'ctl.example.test\n')
        self.assertNotEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        self.assertNotEqual(self.run_cmd('deploy-finish', TEST_ROUTE_FAIL='1').returncode, 0)
        self.assertFalse((self.root / 'run/worker-deployed').exists())
        self.assertNotEqual(self.run_cmd('deploy-finish', TEST_REGEN_FAIL='1').returncode, 0)
        self.assertFalse((self.root / 'run/worker-deployed').exists())
        self.assertEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertEqual(self.run_cmd('deploy-finish').returncode, 0)
        self.assertEqual(self.actions().count('route'), 3)

    def test_remote_binding_blocks_change_without_local_marker(self):
        r = self.run_cmd('set', 'ctl_hostname', 'other', TEST_REMOTE='worker:hometunnel-ctl')
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((self.root / 'etc/worker-bound').exists())
        self.assertEqual(self.actions(), [])

    def test_unknown_remote_ownership_fails_closed(self):
        r = self.run_cmd('set', 'ctl_hostname', 'other', TEST_REMOTE='error:lookup failed')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.root / 'host').exists())

    def test_authentication_failure_never_marks_verified_or_uploads(self):
        r = self.run_cmd('deploy-verify', TEST_REMOTE='worker:hometunnel-ctl', TEST_HEALTH='fail')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.root / 'run/worker-verified').exists())
        self.assertEqual(self.actions(), ['verify'])

    def test_missing_generated_config_never_marks_complete(self):
        (self.root / 'etc/worker-bound').write_bytes(b'ctl.example.test\n')
        self.assertEqual(self.run_cmd('deploy-verify').returncode, 0)
        # Generator may exit zero without writing the actual expected artifact.
        self.assertNotEqual(self.run_cmd('deploy-finish', TEST_NO_CONFIG='1').returncode, 0)
        self.assertFalse((self.root / 'run/worker-deployed').exists())


if __name__ == '__main__':
    unittest.main()
