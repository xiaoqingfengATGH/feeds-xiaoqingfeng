#!/usr/bin/env python3
"""Bounded real browser + owned router fixture lifecycle (WSL root)."""
import json, os, pathlib, signal, socket, subprocess, tempfile, time
HERE = pathlib.Path(__file__).resolve().parent

def listening(port):
    # Read kernel listener state; connect probes may hit host WSL forwarding.
    for table in ['/proc/net/tcp','/proc/net/tcp6']:
        for line in pathlib.Path(table).read_text().splitlines()[1:]:
            fields=line.split()
            if int(fields[1].split(':')[1],16)==port and fields[3]=='0A':return True
    return False

def main():
    assert os.getuid() == 0
    for port in [18993, 18994]:
        assert not listening(port), ('port already occupied', port)
    with tempfile.TemporaryFile(mode='w+') as log:
        proc = subprocess.Popen(['python3', '-u', str(HERE/'rpc-luci-fixture.py')], stdout=log, stderr=log)
        root = None
        try:
            deadline = time.monotonic()+40
            while time.monotonic() < deadline:
                log.seek(0); text = log.read()
                for line in text.splitlines():
                    if line.startswith('FIXTURE_ROOT '):
                        root = line.split(' ', 1)[1]
                if 'READY real rpcd' in text:
                    break
                assert proc.poll() is None, text
                time.sleep(.1)
            else:
                raise AssertionError('fixture readiness timeout: '+text)
            script = HERE.parents[1]/'luci-app-homepublish/tests/product-browser.cjs'
            win = subprocess.check_output(['wslpath','-w',str(script)], text=True).strip()
            subprocess.run(['node.exe',win],check=True,timeout=90)
        finally:
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
            log.seek(0); text=log.read(); print(text,flush=True)
            if root is None:
                for line in text.splitlines():
                    if line.startswith('FIXTURE_ROOT '):root=line.split(' ',1)[1]
            residual=[]
            if root:
                for entry in pathlib.Path('/proc').iterdir():
                    if entry.name.isdigit():
                        for kind in ['root','exe','cwd']:
                            try:
                                target=str((entry/kind).readlink())
                                if target==root or target.startswith(root+'/') or target==root+' (deleted)':residual.append([entry.name,kind,target])
                            except OSError:pass
                mounts=[line for line in pathlib.Path('/proc/self/mountinfo').read_text().splitlines() if root in line]
                assert not mounts,mounts
                assert not pathlib.Path(root).exists(),root
            assert not residual,residual
            for port in [18993,18994]:
                assert not listening(port),port
            print(json.dumps({'cleanup':'PASS','root':root,'owned_processes':residual,'mounts':[],'listeners':[],'directory_absent':True}))

if __name__ == '__main__':main()
