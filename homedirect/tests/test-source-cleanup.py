#!/usr/bin/env python3
"""Root-only isolated chroot regression; real native lease, no networking."""
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class SourceCleanup(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='homedirect-source-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for directory in ('tmp', 'etc/homedirect', 'usr/libexec', 'usr/share/homedirect', 'usr/bin', 'usr/sbin'):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        (self.root / 'tmp').chmod(0o1777)
        (self.root / 'dev').mkdir()
        os.mknod(self.root / 'dev/null', 0o20666, os.makedev(1, 3))
        for utility in ('sh', 'mkdir', 'rm', 'rmdir', 'cp', 'mktemp', 'setsid', 'sleep'):
            binary = pathlib.Path(shutil.which(utility)).resolve()
            self.install(binary, '/bin/' + utility)
            output = subprocess.run(['ldd', str(binary)], text=True, capture_output=True).stdout
            for library in re.findall(r'/[^\s()]+', output):
                if pathlib.Path(library).is_file():
                    self.install(pathlib.Path(library), library)
        self.install(ROOT / 'files/usr/share/homedirect/lease-run.sh', '/usr/share/homedirect/lease-run.sh')
        subprocess.run(['gcc', '-static', '-Wall', '-Wextra', '-Werror', str(ROOT / 'src/lease-supervisor.c'), '-o', str(self.root / 'usr/libexec/homedirect-lease')], check=True)
        fixture = self.root / 'fixture.c'
        fixture.write_text('''#include <string.h>
#include <unistd.h>
#include <stdio.h>
int main(int n,char **a){if(n>1&&!strcmp(a[1],"-t"))return access("/tmp/fail",F_OK)==0?1:0;FILE*f=fopen("/tmp/ready","w");fclose(f);for(;;)sleep(1);}
''')
        subprocess.run(['gcc', '-static', str(fixture), '-o', str(self.root / 'usr/sbin/nginx')], check=True)
        shutil.copy(self.root / 'usr/sbin/nginx', self.root / 'usr/bin/natmap')
        self.runtime = self.root / 'tmp/homedirect-service-Test123'
        self.runtime.mkdir(mode=0o700)
        for name in ('cert.pem', 'key.pem'):
            original = self.root / 'etc/homedirect' / name
            original.write_text('original-' + name)
            original.chmod(0o600)
            shutil.copy(original, self.runtime / name)
        config = self.runtime / 'nginx.conf'
        config.write_text('ssl_certificate /tmp/homedirect-service-Test123/cert.pem;\nssl_certificate_key /tmp/homedirect-service-Test123/key.pem;')
        config.chmod(0o600)

    def install(self, source, target):
        destination = self.root / target.lstrip('/')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(source, destination)
        destination.chmod(0o755)

    def launch(self):
        return subprocess.Popen(['chroot', str(self.root), '/bin/sh', '/usr/share/homedirect/lease-run.sh', '/tmp/homedirect-service-Test123', '2', '18444', '18443', 'example.com', 'example.com'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def wait_ready(self, process):
        deadline = time.monotonic() + 1.5
        while not (self.root / 'tmp/ready').exists():
            if process.poll() is not None or time.monotonic() >= deadline:
                self.fail('lease did not become ready')
            time.sleep(.01)

    def assert_originals(self):
        for name in ('cert.pem', 'key.pem'):
            self.assertEqual((self.root / 'etc/homedirect' / name).read_text(), 'original-' + name)

    def provision_fixture(self, stalled=False):
        (self.root / 'etc/homedirect').chmod(0o700)
        lua = self.root / 'usr/bin/lua'
        lua.write_text('#!/bin/sh\n' + ('echo ready > /tmp/rendering\nsleep 60\n' if stalled else '') +
                       'printf "ssl_certificate %s/cert.pem;\\nssl_certificate_key %s/key.pem;\\n" "$4" "$4"\n')
        lua.chmod(0o755)

    def launch_provision(self, stalled=False):
        self.provision_fixture(stalled)
        return subprocess.Popen(['chroot', str(self.root), '/usr/libexec/homedirect-lease', '--provision', '3', '18444', '18443', 'example.com', 'example.com'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def wait_rendering(self, process):
        deadline = time.monotonic() + 1.5
        while not (self.root / 'tmp/rendering').exists():
            if process.poll() is not None or time.monotonic() > deadline:
                self.fail('provisioning did not reach monitored renderer')
            time.sleep(.01)

    def assert_provision_cleanup(self):
        paths = list((self.root / 'tmp').glob('homedirect-service-*'))
        self.assertEqual(paths, [self.runtime], 'owned provision directory retained or foreign runtime deleted')
        self.assertEqual((self.runtime / 'key.pem').read_text(), 'original-key.pem')
        self.assert_originals()

    def test_native_provision_expiry(self):
        process = self.launch_provision()
        self.wait_ready(process)
        output = process.communicate(timeout=6)[1]
        self.assertEqual(process.returncode, 0, output)
        self.assert_provision_cleanup()

    def test_native_provision_concurrent_leases_are_isolated(self):
        first = self.launch_provision()
        self.wait_ready(first)
        (self.root / 'tmp/ready').unlink()
        second = self.launch_provision()
        try:
            self.wait_ready(second)
            self.assertEqual(len(list((self.root / 'tmp').glob('homedirect-service-*'))), 3)
        finally:
            first.communicate(timeout=6)
            second.communicate(timeout=6)
        self.assertEqual(second.returncode, 0)
        self.assert_provision_cleanup()

    def test_native_provision_renderer_exec_failure(self):
        self.provision_fixture()
        (self.root / 'usr/bin/lua').unlink()
        process = subprocess.Popen(['chroot', str(self.root), '/usr/libexec/homedirect-lease', '--provision', '3', '18444', '18443', 'example.com', 'example.com'], stderr=subprocess.PIPE)
        process.communicate(timeout=6)
        self.assertNotEqual(process.returncode, 0)
        self.assert_provision_cleanup()

    def test_native_provision_replacement_sources_preserved(self):
        process = self.launch_provision()
        self.wait_ready(process)
        generated = next(p for p in (self.root / 'tmp').glob('homedirect-service-*') if p != self.runtime)
        (generated / 'key.pem').rename(generated / 'saved-key.pem')
        (generated / 'key.pem').write_text('replacement')
        (generated / 'unknown').write_text('foreign')
        process.communicate(timeout=6)
        self.assertEqual((generated / 'key.pem').read_text(), 'replacement')
        self.assertEqual((generated / 'unknown').read_text(), 'foreign')
        self.assertFalse((generated / 'cert.pem').exists())
        self.assert_originals()

    def test_native_provision_replacement_directory_preserved(self):
        process = self.launch_provision()
        self.wait_ready(process)
        generated = next(p for p in (self.root / 'tmp').glob('homedirect-service-*') if p != self.runtime)
        generated.rename(generated.with_name('homedirect-service-MovedNative'))
        generated.mkdir(mode=0o700)
        (generated / 'key.pem').write_text('replacement directory')
        process.communicate(timeout=6)
        self.assertEqual((generated / 'key.pem').read_text(), 'replacement directory')
        self.assert_originals()

    def test_native_provision_controller_kill_during_render(self):
        process = self.launch_provision(stalled=True)
        self.wait_rendering(process)
        process.kill()
        process.communicate(timeout=6)
        deadline = time.monotonic() + 4
        while len(list((self.root / 'tmp').glob('homedirect-service-*'))) > 1 and time.monotonic() < deadline:
            time.sleep(.02)
        self.assert_provision_cleanup()

    def test_native_provision_preparation_kill_during_render(self):
        import signal
        process = self.launch_provision(stalled=True)
        self.wait_rendering(process)
        guardian = self.children(process.pid)[0]
        preparation = self.children(guardian)[0]
        os.kill(preparation, signal.SIGKILL)
        process.communicate(timeout=6)
        self.assertNotEqual(process.returncode, 0)
        self.assert_provision_cleanup()

    def test_native_provision_preparation_stop_during_render(self):
        import signal
        process = self.launch_provision(stalled=True)
        self.wait_rendering(process)
        guardian = self.children(process.pid)[0]
        os.kill(self.children(guardian)[0], signal.SIGSTOP)
        process.communicate(timeout=6)
        self.assertNotEqual(process.returncode, 0)
        self.assert_provision_cleanup()

    def test_native_provision_guardian_kill_during_render(self):
        import signal
        process = self.launch_provision(stalled=True)
        self.wait_rendering(process)
        os.kill(self.children(process.pid)[0], signal.SIGKILL)
        process.communicate(timeout=6)
        self.assertNotEqual(process.returncode, 0)
        self.assert_provision_cleanup()

    def test_native_provision_guardian_stop_during_render(self):
        import signal
        process = self.launch_provision(stalled=True)
        self.wait_rendering(process)
        os.kill(self.children(process.pid)[0], signal.SIGSTOP)
        process.communicate(timeout=6)
        self.assertNotEqual(process.returncode, 0)
        self.assert_provision_cleanup()

    def test_native_provision_controller_stop_during_render(self):
        import signal
        process = self.launch_provision(stalled=True)
        self.wait_rendering(process)
        os.kill(process.pid, signal.SIGSTOP)
        try:
            time.sleep(3.5)
            self.assert_provision_cleanup()
        finally:
            os.kill(process.pid, signal.SIGCONT)
            process.communicate(timeout=6)

    def test_init_death_and_later_submission_rejection_create_no_sources(self):
        shutil.rmtree(self.runtime)
        self.install(ROOT / 'files/etc/init.d/homedirect', '/homedirect.init')
        self.provision_fixture()
        header = '''. /homedirect.init
homedirect_plan() { printf 'configured\\n2\\n18444\\n18443\\nexample.com\\nexample.com\\n'; }
procd_open_instance() { :; }
procd_set_param() { :; }
procd_close_instance() { :; }
'''
        for tail in ('homedirect_plan() { kill -KILL $$; }; start_service',
                     'procd_open_instance() { kill -KILL $$; }; start_service',
                     'start_service; kill -KILL $$',
                     'start_service || exit 2; exit 1'):
            with self.subTest(tail=tail):
                result = subprocess.run(['chroot', str(self.root), '/bin/sh', '-c', header + tail], capture_output=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list((self.root / 'tmp').glob('homedirect-service-*')), [])
                self.assert_originals()

    def test_native_metadata_without_stat(self):
        self.assertFalse((self.root / 'bin/stat').exists())
        helper = ['chroot', str(self.root), '/usr/libexec/homedirect-lease']
        for path in (self.runtime, self.runtime / 'key.pem'):
            st = path.stat()
            identity = subprocess.run(helper + ['--identity', '/'+path.relative_to(self.root).as_posix()], text=True, capture_output=True)
            self.assertEqual(identity.returncode, 0, identity.stderr)
            self.assertEqual(identity.stdout.strip(), f'{st.st_dev}:{st.st_ino}')
        result = subprocess.run(helper + ['--metadata', '/etc/homedirect/key.pem'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '0:600:1')
        (self.runtime / 'link').symlink_to('key.pem')
        for path in ('/tmp/homedirect-service-Test123/link', '/missing'):
            result = subprocess.run(helper + ['--identity', path], text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')

    def test_adapter_sigkill_removes_owned_sources(self):
        process = self.launch()
        self.wait_ready(process)
        process.kill()
        process.communicate(timeout=7)
        self.assertFalse(self.runtime.exists(), 'adapter SIGKILL retained owned TLS sources')
        self.assert_originals()

    def children(self, pid):
        path = pathlib.Path('/proc') / str(pid) / 'task' / str(pid) / 'children'
        return [int(p) for p in path.read_text().split()] if path.exists() else []

    def test_adapter_stop_does_not_delay_cleanup(self):
        import signal
        process = self.launch()
        self.wait_ready(process)
        os.kill(process.pid, signal.SIGSTOP)
        try:
            deadline = time.monotonic() + 5
            while self.runtime.exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertFalse(self.runtime.exists(), 'stopped adapter prevented cleanup')
            self.assert_originals()
        finally:
            os.kill(process.pid, signal.SIGCONT)
            process.communicate(timeout=5)

    def test_controller_sigkill_removes_owned_sources(self):
        import signal
        process = self.launch()
        self.wait_ready(process)
        watcher = self.children(process.pid)[0]
        controller = self.children(watcher)[0]
        os.kill(controller, signal.SIGKILL)
        process.communicate(timeout=7)
        self.assertFalse(self.runtime.exists(), 'controller SIGKILL retained sources')
        self.assert_originals()

    def test_guardian_sigkill_removes_owned_sources(self):
        import signal
        process = self.launch()
        self.wait_ready(process)
        watcher = self.children(process.pid)[0]
        controller = self.children(watcher)[0]
        guardian = self.children(controller)[0]
        os.kill(guardian, signal.SIGKILL)
        process.communicate(timeout=7)
        self.assertFalse(self.runtime.exists())
        self.assert_originals()

    def test_natmap_exec_failure_removes_owned_sources(self):
        (self.root / 'usr/bin/natmap').unlink()
        process = self.launch()
        process.communicate(timeout=7)
        self.assertNotEqual(process.returncode, 0)
        self.assertFalse(self.runtime.exists())
        self.assert_originals()

    def engine_exit(self, executable):
        import signal
        process = self.launch()
        self.wait_ready(process)
        watcher = self.children(process.pid)[0]
        controller = self.children(watcher)[0]
        guardian = self.children(controller)[0]
        phase = self.children(guardian)[0]
        deadline = time.monotonic() + 1
        while True:
            engines = self.children(phase)
            matches = [p for p in engines if pathlib.Path('/proc', str(p), 'comm').read_text().strip() == executable]
            if matches:
                break
            if time.monotonic() >= deadline:
                self.fail('engine not started: ' + executable)
            time.sleep(.01)
        os.kill(matches[0], signal.SIGKILL)
        process.communicate(timeout=7)
        self.assertFalse(self.runtime.exists())
        self.assert_originals()

    def test_nginx_exit_removes_owned_sources(self):
        self.engine_exit('nginx')

    def test_natmap_exit_removes_owned_sources(self):
        self.engine_exit('natmap')

    def test_normal_expiry_removes_private_sources(self):
        process = self.launch()
        output = process.communicate(timeout=5)[1]
        self.assertEqual(process.returncode, 0, output.decode())
        self.assertFalse(self.runtime.exists(), 'generated TLS source directory retained after expiry')
        self.assert_originals()

    def test_init_registers_native_provisioner(self):
        self.install(ROOT / 'files/etc/init.d/homedirect', '/homedirect.init')
        self.install(pathlib.Path(shutil.which('cp')).resolve(), '/bin/cp')
        self.install(pathlib.Path(shutil.which('mktemp')).resolve(), '/bin/mktemp')
        lua = self.root / 'bin/lua'
        lua.write_text('#!/bin/sh\necho rendered\n')
        lua.chmod(0o755)
        script = '''. /homedirect.init
homedirect_plan() { printf 'configured\\n2\\n18444\\n18443\\nexample.com\\nexample.com\\n'; }
procd_open_instance() { :; }
procd_set_param() { [ "$1" != command ] || printf '%s\\n' "$2"; }
procd_close_instance() { :; }
start_service
'''
        result = subprocess.run(['chroot', str(self.root), '/bin/sh', '-c', script], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '/usr/libexec/homedirect-lease')

    def test_init_registration_failure_removes_private_sources(self):
        shutil.rmtree(self.runtime)
        self.install(ROOT / 'files/etc/init.d/homedirect', '/homedirect.init')
        lua = self.root / 'bin/lua'
        lua.write_text('#!/bin/sh\necho rendered\n')
        lua.chmod(0o755)
        script = '''. /homedirect.init
homedirect_plan() { printf 'configured\\n2\\n18444\\n18443\\nexample.com\\nexample.com\\n'; }
procd_open_instance() { :; }
procd_set_param() { :; }
procd_close_instance() { return 1; }
start_service
'''
        result = subprocess.run(['chroot', str(self.root), '/bin/sh', '-c', script], text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((self.root / 'tmp').glob('homedirect-service-*')), [], 'failed registration retained provisioned TLS sources')
        self.assert_originals()

    def test_failure_before_detached_watcher_leaves_no_sources(self):
        # New startup path must never pre-create TLS for a shell watcher.
        shutil.rmtree(self.runtime)
        self.install(ROOT / 'files/etc/init.d/homedirect', '/homedirect.init')
        setsid = self.root / 'bin/setsid'
        setsid.unlink()
        setsid.write_text('#!/bin/sh\nexit 1\n')
        setsid.chmod(0o755)
        lua = self.root / 'usr/bin/lua'
        lua.write_text('#!/bin/sh\nprintf "ssl_certificate %s/cert.pem;\\nssl_certificate_key %s/key.pem;\\n" "$4" "$4"\n')
        lua.chmod(0o755)
        (self.root / 'etc/homedirect').chmod(0o700)
        script = '''. /homedirect.init
homedirect_plan() { printf 'configured\\n2\\n18444\\n18443\\nexample.com\\nexample.com\\n'; }
procd_open_instance() { :; }
procd_set_param() { if [ "$1" = command ]; then shift; printf '%s ' "$@" > /tmp/command; fi; }
procd_close_instance() { :; }
start_service || exit 1
/bin/sh /tmp/command
'''
        result = subprocess.run(['chroot', str(self.root), '/bin/sh', '-c', script], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'tmp/ready').exists(), 'registered native provisioning never reached engines')
        self.assertEqual(list((self.root / 'tmp').glob('homedirect-service-*')), [], result.stderr)
        self.assert_originals()

    def test_startup_failure_removes_private_sources(self):
        (self.root / 'tmp/fail').touch()
        process = self.launch()
        process.communicate(timeout=5)
        self.assertNotEqual(process.returncode, 0)
        self.assertFalse(self.runtime.exists())
        self.assert_originals()

    def test_disable_term_removes_private_sources(self):
        process = self.launch()
        self.wait_ready(process)
        process.terminate()
        process.communicate(timeout=5)
        self.assertFalse(self.runtime.exists())
        self.assert_originals()

    def test_competing_adapter_preserves_active_runtime(self):
        process = self.launch()
        self.wait_ready(process)
        competing = self.launch()
        competing.communicate(timeout=3)
        self.assertNotEqual(competing.returncode, 0)
        self.assertTrue((self.runtime / 'runner.lock/cert.pem').exists())
        self.assertTrue((self.runtime / 'key.pem').exists())
        self.assertIsNone(process.poll())
        process.communicate(timeout=5)
        self.assertFalse(self.runtime.exists())
        self.assert_originals()

    def test_preexisting_competing_snapshot_is_untouched(self):
        snapshot = self.runtime / 'runner.lock'
        snapshot.mkdir(mode=0o700)
        (snapshot / 'key.pem').write_text('competing snapshot')
        process = self.launch()
        process.communicate(timeout=3)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual((snapshot / 'key.pem').read_text(), 'competing snapshot')
        self.assertEqual((self.runtime / 'key.pem').read_text(), 'original-key.pem')
        self.assert_originals()

    def test_replaced_runtime_directory_is_untouched(self):
        process = self.launch()
        self.wait_ready(process)
        moved = self.runtime.with_name('homedirect-service-Moved123')
        self.runtime.rename(moved)
        self.runtime.mkdir(mode=0o700)
        (self.runtime / 'key.pem').write_text('competing runtime')
        process.communicate(timeout=5)
        self.assertEqual((self.runtime / 'key.pem').read_text(), 'competing runtime')
        self.assert_originals()

    def test_replaced_source_and_unknown_files_are_preserved(self):
        process = self.launch()
        self.wait_ready(process)
        # Keep the previous inode allocated so replacement cannot reuse it.
        (self.runtime / 'key.pem').rename(self.runtime / 'saved-key.pem')
        (self.runtime / 'key.pem').write_text('competing replacement')
        (self.runtime / 'unknown').write_text('unowned')
        process.communicate(timeout=5)
        self.assertEqual((self.runtime / 'key.pem').read_text(), 'competing replacement')
        self.assertEqual((self.runtime / 'unknown').read_text(), 'unowned')
        self.assertFalse((self.runtime / 'cert.pem').exists())
        self.assertFalse((self.runtime / 'runner.lock').exists())
        self.assert_originals()

if __name__ == '__main__':
    unittest.main()
