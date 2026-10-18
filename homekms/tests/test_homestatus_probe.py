"""Isolated HomeStatus probe tests; no router, ubus, UCI writes or real processes."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

PACKAGE = Path(__file__).resolve().parents[1]
PROBE = PACKAGE / 'files/etc/homestatus-probes/homekms'


def load_probe():
    loader = importlib.machinery.SourceFileLoader('homekms_probe', str(PROBE))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class ProbeTests(unittest.TestCase):
    def test_checked_service_process_is_running_without_listener(self):
        self.assertTrue(PROBE.is_file(), 'HomeStatus probe is missing')
        probe = load_probe()
        with tempfile.TemporaryDirectory() as root:
            pid = Path(root) / '42'
            pid.mkdir()
            (pid / 'cmdline').write_bytes(b'\0'.join([
                b'/usr/bin/python3', b'-B', b'-u',
                b'/usr/share/homekms/pykms/pykms_Server.py', b'0.0.0.0',
                b'1688', b'-F', b'STDOUT', b'']))
            (pid / 'fd').mkdir()
            (pid / 'net').mkdir()
            (pid / 'net/tcp').write_text('header\n')
            self.assertEqual(probe.process_state(root), 0)


    def test_stopped_and_unrelated_python_are_not_running(self):
        probe = load_probe()
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(probe.process_state(root), 1)
            pid = Path(root) / '17'
            pid.mkdir()
            (pid / 'cmdline').write_bytes(b'/usr/bin/python3\0other.py\0homekms\0')
            self.assertEqual(probe.process_state(root), 1)
            (pid / 'cmdline').write_bytes(b'')  # kernel thread/zombie
            self.assertEqual(probe.process_state(root), 1)

    def test_missing_or_unreadable_proc_is_unknown(self):
        probe = load_probe()
        with patch.object(probe.os, 'listdir', side_effect=PermissionError()):
            self.assertEqual(probe.process_state(), 2)
        with tempfile.TemporaryDirectory() as root:
            pid = Path(root) / '42'
            pid.mkdir()
            self.assertEqual(probe.process_state(root), 2)
            (pid / 'cmdline').write_bytes(b'\0'.join(probe.SERVICE_ARGV) + b'\0')
            self.assertEqual(probe.process_state(root), 2)  # missing fd
            (pid / 'fd').mkdir()
            (pid / 'net').mkdir()
            self.assertEqual(probe.process_state(root), 2)  # missing tcp
            (pid / 'net/tcp').write_text('header\n')
            self.assertEqual(probe.process_state(root), 0)  # optional tcp6 absent
            with patch.object(probe.os, 'readlink', side_effect=PermissionError()):
                (pid / 'fd/3').write_text('fixture')
                self.assertEqual(probe.process_state(root), 2)
            with patch.object(probe.os, 'readlink', side_effect=FileNotFoundError()):
                self.assertEqual(probe.process_state(root), 0)  # closing fd

    def test_cli_port_validation_fallback_and_read_only_command(self):
        probe = load_probe()
        with patch.object(probe.sys, 'argv', ['homekms']), \
             patch.object(probe, 'process_state', return_value=0) as state:
            for value in (b'1024', b'1688\n', b'65535'):
                with self.subTest(value=value), patch.object(probe.subprocess, 'check_output', return_value=value) as command:
                    self.assertEqual(probe.main(), 0)
                    command.assert_called_once_with(['/sbin/uci', '-q', 'get', 'homekms.main.port'],
                                                    stderr=subprocess.DEVNULL, timeout=3)
            for value in (b'', b'1023', b'65536', b'1688;id', b'-1', b'999999', b'\xff'):
                state.reset_mock()
                with self.subTest(value=value), patch.object(probe.subprocess, 'check_output', return_value=value):
                    self.assertEqual(probe.main(), 2)
                    state.assert_not_called()
            with patch.object(probe.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(1, 'uci')):
                self.assertEqual(probe.main(), 0)
            for error in (FileNotFoundError(), PermissionError(), subprocess.TimeoutExpired('uci', 3)):
                with self.subTest(error=error), patch.object(probe.subprocess, 'check_output', side_effect=error):
                    self.assertEqual(probe.main(), 2)
        with patch.object(probe.sys, 'argv', ['homekms', 'start']), \
             patch.object(probe.subprocess, 'check_output') as command:
            self.assertEqual(probe.main(), 2)
            command.assert_not_called()

    def test_cli_exit_codes_and_quiet_argument_rejection(self):
        import sys
        probe = load_probe()
        for state in (0, 1, 2):
            with self.subTest(state=state), patch.object(probe.sys, 'argv', ['homekms']), \
                 patch.object(probe.subprocess, 'check_output', return_value=b'1688'), \
                 patch.object(probe, 'process_state', return_value=state):
                self.assertEqual(probe.main(), state)
        result = subprocess.run([sys.executable, '-B', str(PROBE), 'start'],
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertEqual((result.stdout, result.stderr), (b'', b''))

    def test_command_identity_stays_in_sync_with_init(self):
        probe = load_probe()
        init = (PACKAGE / 'files/etc/init.d/homekms').read_text()
        self.assertIn('procd_set_param command ' +
                      ' '.join(arg.decode() for arg in probe.SERVICE_ARGV), init)

    def test_install_sets_executable_mode(self):
        make = (PACKAGE / 'Makefile').read_text()
        self.assertIn('$(CP) ./files/* $(1)/', make)
        self.assertIn('$(1)/etc/homestatus-probes/homekms',
                      next(line for line in make.splitlines() if line.startswith('\tchmod 0755')))
        self.assertEqual(PROBE.read_text().splitlines()[0], '#!/usr/bin/python3 -B')


if __name__ == '__main__':
    unittest.main()
