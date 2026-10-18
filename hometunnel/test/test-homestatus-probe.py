"""Isolated probe tests: python hometunnel/test/test-homestatus-probe.py.

No router, network, real UCI or live /proc is used. Rewrite only the proc path
in a temporary copy, and record/reject lifecycle, ubus and network commands.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PACKAGE = Path(__file__).resolve().parents[1]
SOURCE = PACKAGE / 'files/etc/homestatus-probes/hometunnel'
CTL = ['/bin/sh', '/usr/share/hometunnel/ctl-loop.sh']
TUNNEL = ['/usr/bin/cloudflared', 'tunnel', '--no-autoupdate', '--config',
          '/etc/hometunnel/config.yml', '--metrics', '127.0.0.1:20241', 'run']


class ProbeTest(unittest.TestCase):
    def setUp(self):
        scratch = os.environ.get('TMPDIR')
        if not scratch and os.name == 'nt':
            scratch = str(Path.home() / 'AppData/Local/hermes/cache/scratch')
        self.tmp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.proc = self.root / 'proc'
        (self.proc / 'self').mkdir(parents=True)
        (self.proc / 'self/stat').write_text('test')
        self.process(1, ['/sbin/procd'])
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.calls = self.root / 'calls'
        uci = self.bin / 'uci'
        uci.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
[ "$1" = -q ] && [ "$2" = get ] || exit 90
case "$3" in
hometunnel.global) [ "$SECTION" = missing ] && exit 1; echo "$SECTION" ;;
hometunnel.global.mode) [ "$MODE" = absent ] && exit 1; echo "$MODE" ;;
*) exit 90 ;;
esac
''')
        uci.chmod(0o755)
        for cmd in ['ubus', 'curl', 'wget', 'service', 'logger', 'hometunnel.sh']:
            path = self.bin / cmd
            path.write_text('#!/bin/sh\necho FORBIDDEN >> "$CALLS"\nexit 99\n')
            path.chmod(0o755)
        self.script = self.root / 'probe.sh'
        text = SOURCE.read_text()
        self.assertEqual(text.count('proc=/proc'), 1)
        self.script.write_text(text.replace('proc=/proc', 'proc=' + self.proc.as_posix()))
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        MODE='ondemand', SECTION='hometunnel', CALLS=str(self.calls))

    def process(self, pid, argv):
        directory = self.proc / str(pid)
        directory.mkdir(exist_ok=True)
        (directory / 'cmdline').write_bytes(b'\0'.join(x.encode() for x in argv) + b'\0')

    def check(self, expected, mode='ondemand', section='hometunnel'):
        before = {p.relative_to(self.proc): p.read_bytes() for p in self.proc.rglob('*') if p.is_file()}
        result = subprocess.run([shutil.which('sh'), str(self.script)], env=dict(self.env, MODE=mode, SECTION=section),
                                capture_output=True, timeout=5)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (expected, b'', b''))
        calls = self.calls.read_text().splitlines()
        self.assertTrue(all(c in ['-q get hometunnel.global', '-q get hometunnel.global.mode'] for c in calls))
        self.assertEqual(before, {p.relative_to(self.proc): p.read_bytes() for p in self.proc.rglob('*') if p.is_file()})

    def test_idle_control_is_running(self):
        self.process(10, CTL)
        self.check(0)

    def test_control_stopped_even_when_data_running(self):
        self.process(10, TUNNEL)
        self.check(1)

    def test_alwayson_data(self):
        self.process(10, TUNNEL)
        self.check(0, 'alwayson')

    def test_alwayson_ignores_control(self):
        self.process(10, CTL)
        self.check(1, 'alwayson')

    def test_no_process(self):
        self.check(1)

    def test_default_mode(self):
        self.process(10, CTL)
        self.check(0, 'absent')

    def test_unknown_mode(self):
        self.check(2, 'invalid')

    def test_missing_or_invalid_config(self):
        for section in ['missing', 'invalid']:
            self.check(2, section=section)

    def test_missing_proc(self):
        (self.proc / 'self/stat').unlink()
        self.check(2)

    def test_unreadable_process(self):
        (self.proc / '1/cmdline').unlink()
        self.check(2)

    def test_positive_overrides_unreadable_other_process(self):
        (self.proc / '1/cmdline').unlink()
        self.process(10, CTL)
        self.check(0)

    def test_control_lookalikes(self):
        for i, args in enumerate([['echo', *CTL], [*CTL, 'status'],
                                   ['/bin/sh', CTL[1] + '.old']], 10):
            self.process(i, args)
        self.check(1)

    def test_data_lookalikes(self):
        cases = [['echo', *TUNNEL], [*TUNNEL[:-1], 'list'],
                 [x.replace('/etc/hometunnel/config.yml', '/etc/other.yml') for x in TUNNEL],
                 ['/usr/bin/cloudflared', 'tunnel', '--url', 'http://localhost', 'run']]
        for i, args in enumerate(cases, 10):
            self.process(i, args)
        self.check(1, 'alwayson')

    def test_kernel_thread(self):
        self.process(10, [])
        self.check(1)

    def test_package_install(self):
        makefile = (PACKAGE / 'Makefile').read_text()
        recipe = makefile.split('define Package/hometunnel/install\n', 1)[1].split('\nendef', 1)[0]
        stage = self.root / 'stage'
        recipe = recipe.replace('$(1)', stage.as_posix()).replace('$(INSTALL_DIR)', 'install -d')
        recipe = recipe.replace('$(INSTALL_BIN)', 'install -m 0755').replace('$(INSTALL_CONF)', 'install -m 0600')
        recipe = recipe.replace('$(INSTALL_DATA)', 'install -m 0644')
        result = subprocess.run([shutil.which('sh'), '-ec', recipe], cwd=PACKAGE, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        installed = stage / 'etc/homestatus-probes/hometunnel'
        self.assertEqual(installed.read_bytes(), SOURCE.read_bytes())
        result = subprocess.run([shutil.which('sh'), '-n', str(installed)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
