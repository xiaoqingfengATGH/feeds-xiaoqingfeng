"""Exercise the real firewall helper with filesystem/command paths isolated."""
import pathlib
import subprocess
import tempfile
import unittest
import os
import shutil

BASH = os.environ.get('HOMEKMS_TEST_BASH') or shutil.which('bash')

def shell_path(path):
    value = path.as_posix()
    if len(value) > 2 and value[1] == ':':
        return '/' + value[0].lower() + value[2:]
    return value

INIT = pathlib.Path(__file__).resolve().parents[1] / 'files/etc/init.d/homekms'


class FirewallReload(unittest.TestCase):
    def test_running_stopped_and_failed_firewall(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            state = root / 'fw4.state'
            events = root / 'events'
            fw4 = root / 'fw4'
            fw4.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "' + shell_path(events) + '"\nexit "${FAIL_FW4:-0}"\n')
            # The init is sourced, never installed or run through host rc.common.
            source = INIT.read_text().replace('/var/run/fw4.state', shell_path(state)).replace('/sbin/fw4 reload', 'bash "' + shell_path(fw4) + '" reload')
            isolated = root / 'init'
            isolated.write_text(source)
            command = [BASH, '-c', '. "' + shell_path(isolated) + '"; service_started']
            self.assertEqual(subprocess.run(command).returncode, 0)
            self.assertFalse(events.exists(), 'must not start an administratively stopped firewall')
            state.touch()
            self.assertEqual(subprocess.run(command).returncode, 0)
            self.assertEqual(events.read_text(), 'reload\n')
            failed = [BASH, '-c', '. "' + shell_path(isolated) + '"; FAIL_FW4=7; export FAIL_FW4; service_started']
            self.assertEqual(subprocess.run(failed).returncode, 7)


if __name__ == '__main__':
    unittest.main()
