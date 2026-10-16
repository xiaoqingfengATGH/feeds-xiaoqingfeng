"""Independent vlmcs C client; never modifies host product licensing."""
import argparse, pathlib, subprocess, sys, tempfile, time, socket

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--server-dir', required=True, type=pathlib.Path)
    p.add_argument('--client', required=True)
    a = p.parse_args()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    with tempfile.TemporaryFile() as log:
        server = subprocess.Popen([sys.executable, '-B', '-u', str(a.server_dir/'pykms_Server.py'), '127.0.0.1', str(port), '-F', 'STDOUT'], stdout=log, stderr=log)
        try:
            time.sleep(2)
            assert server.poll() is None, 'server exited during startup'
            for version in (4, 5, 6):
                for product in ('5', '20', '174'):
                    for mode, options in (('reuse', []), ('new', ['-T'])):
                        r = subprocess.run([a.client, '-v', *options, f'-{version}', '-l', product, '-n', '3', f'127.0.0.1:{port}'], capture_output=True, text=True, timeout=30)
                        output = r.stdout+r.stderr
                        assert r.returncode == 0, output
                        assert 'Error' not in output and 'failed' not in output.lower(), output
                        # vlmcs silently reconnects when an emulator closes the socket;
                        # successful responses alone do not prove connection reuse.
                        assert 'Server closed RPC connection' not in output, output
                        expected_connections = 1 if mode == 'reuse' else 3
                        assert output.count('Connecting to ') == expected_connections, output
                        assert output.count('Performing RPC bind') == expected_connections, output
                        assert output.count('Response from KMS server') == 3, output
                        assert 'KMS host extended PID' in output, output
                        assert 'success' in output.lower(), output
                        print(f'PASS mode={mode} v{version} product={product} requests=3 response checks: '+output[-250:].replace('\n', ' '))
            log.seek(0); text=log.read().decode(errors='replace')
            assert 'Traceback' not in text and 'Exception' not in text, text
        finally:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired: server.kill(); server.wait()
if __name__ == '__main__': main()
