import os
from pathlib import Path
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[1] / 'files/usr/share/hometunnel/gen-yml.sh'

with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as td:
    tmp = Path(td)
    conf = tmp / 'conf'
    (conf / '.cloudflared').mkdir(parents=True)
    (conf / '.cloudflared' / 'test-id.json').write_text('{}')
    uci = tmp / 'uci'
    uci.write_text('''#!/bin/sh
case "$*" in
  "-q show hometunnel") echo 'hometunnel.@ingress[0]=ingress'; echo 'hometunnel.@ingress[1]=ingress'; echo 'hometunnel.@ingress[2]=ingress'; echo 'hometunnel.@ingress[3]=ingress' ;;
  *global.tunnel_id) echo test-id ;;
  *global.domain) echo example.org ;;
  *'@ingress[0].service') echo http://192.168.1.1:80 ;;
  *'@ingress[1].service') echo https://nas.lan:443 ;;
  *'@ingress[2].service') echo ssh://192.168.1.3:22 ;;
  *'@ingress[3].service') echo http://192.168.1.4:8080 ;;
  *'@ingress[0].subdomain') echo mi ;;
  *'@ingress[1].subdomain') echo nas ;;
  *'@ingress[2].subdomain') echo ssh ;;
  *'@ingress[3].subdomain') echo manual ;;
  *'@ingress[3].http_host_header') echo custom.lan ;;
  *.enabled) echo 1 ;;
  *) exit 1 ;;
esac
''')
    uci.chmod(0o755)
    text = SOURCE.read_text().replace('CONF_DIR=/etc/hometunnel', f'CONF_DIR={conf.as_posix()}').replace('[ -x /sbin/uci ]', '[ -x "$(command -v uci)" ]').replace('log() { logger -t hometunnel "$*"; }', 'log() { :; }')
    script = tmp / 'gen.sh'
    script.write_text(text)
    env = dict(os.environ, PATH=str(tmp) + os.pathsep + os.environ['PATH'])
    result = subprocess.run(['sh', str(script), str(tmp/'out.yml')], env=env, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    generated = (tmp/'out.yml').read_text()
    for hostname, expected in [('mi', '192.168.1.1'), ('nas', 'nas.lan'), ('manual', 'custom.lan')]:
        block = generated.split('hostname: '+hostname+'.example.org')[1].split('  - hostname:', 1)[0]
        assert 'httpHostHeader: '+expected in block, (hostname, block)
    ssh_block = generated.split('hostname: ssh.example.org')[1].split('  - hostname:', 1)[0]
    assert 'httpHostHeader:' not in ssh_block, ssh_block
print('ingress default host headers: PASS')
