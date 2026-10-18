"""Run HTTP regressions and real Nginx syntax checks in a private device root.
Never installs source, starts components, changes config, or touches firewall.
"""
import argparse
import importlib.util
import io
import pathlib
import shlex
import subprocess
import tarfile
import unittest
import uuid

HERE = pathlib.Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='192.168.1.2')
    parser.add_argument('--key', default='D:/DevPortal/CloudHosts/HomePri.key')
    args = parser.parse_args()
    ssh = ['ssh', '-i', args.key, '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', 'root@'+args.host]
    root = '/root/homepublish-http-regression-'+uuid.uuid4().hex
    def remote(command, data=None):
        r = subprocess.run(ssh+[command], input=data, capture_output=True)
        if r.returncode:
            raise RuntimeError(r.stdout.decode()+r.stderr.decode())
        return r.stdout.decode()+r.stderr.decode()
    spec = importlib.util.spec_from_file_location('http_ingress', HERE/'test-http-ingress.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    class DeviceHTTPTests(module.HTTPIngressTests):
        def run_lua(self, body):
            remote('lua -', ('source='+repr(root)+'\n'+module.SETUP+body).encode())
    try:
        remote('mkdir -m 700 '+shlex.quote(root));remote('mkdir '+shlex.quote(root+'/logs'))
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w') as t:
            for p in module.SOURCE.glob('*.lua'):
                t.add(p, arcname=p.name)
        remote('tar -xf - -C '+shlex.quote(root), archive.getvalue())
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(DeviceHTTPTests))
        if not result.wasSuccessful(): return 1
        print(remote('openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=web.example -keyout '+root+'/key.pem -out '+root+'/cert.pem 2>/dev/null'))
        body = '''
providers.certificate_snapshot=function()return {certificate=source..'/cert.pem',key=source..'/key.pem'}end
for _,mixed in ipairs({false,true}) do
 local services={service('http_proxy','http')}
 if mixed then services[2]=service('https_proxy','https');services[3]=service('tls_passthrough','tls');services[4]=service('ssh','ssh');services[5]=service('tcp_forward','tcp') end
 local c=config(services);c.access_profile.listeners[1].address='192.168.1.2';if mixed then c.default_certificate_ref='import:test' end
 local r=rendered(c);local name=mixed and 'mixed' or 'http'
 local f=assert(io.open(source..'/'..name..'.conf','w'));f:write(r.configuration);f:close()
end
'''
        remote('lua -', ('source='+repr(root)+'\n'+module.SETUP+body).encode())
        for name in ('http', 'mixed'):
            print(remote('/usr/libexec/homepublish/nginx -t -p '+root+'/ -c '+root+'/'+name+'.conf'))
        print(remote('/usr/libexec/homepublish/sslh-select --version'))
        print('DEVICE_HTTP_CANONICAL_RENDER_NGINX_SYNTAX_GREEN')
        return 0
    finally:
        remote('rm -rf '+shlex.quote(root))
        remote('test ! -e '+shlex.quote(root))

if __name__ == '__main__':
    raise SystemExit(main())
