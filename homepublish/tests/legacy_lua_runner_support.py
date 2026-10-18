"""Fail-closed preparation for legacy private controller runners."""
import hashlib,json
from p5_resume_support import upload
REMOTE='/tmp/homepublish-tcp-p3'
def prepare_legacy_fixture(ssh, root):
 # All conflict checks precede fixture writes and any lifecycle try/finally.
 state=ssh('sha256sum /etc/homepublish/product/state').stdout.split()[0]
 services=json.loads(ssh('ubus call service list').stdout)
 for name in ('homepublish-p3-controller','homepublish-p3-backend','homepublish-p3-clients','homepublish-p3-blocker','homepublish-p4-policy'):
  if name in services: raise RuntimeError('fixture service conflict: '+name)
 ssh('test ! -e '+REMOTE+'/controller-fixture && test ! -e '+REMOTE+'/controller-runtime && test ! -e /root/homepublish-p3-controller-auth')
 # Validate deployed production bytes, not a staged replacement, before injection.
 for name in ('product-provider.lua','product-store.lua','product-store-core.lua'):
  expected=hashlib.sha256((root/'homepublish/files/usr/share/homepublish'/name).read_bytes()).hexdigest()
  actual=ssh('sha256sum /usr/share/homepublish/'+name).stdout.split()[0]
  if expected!=actual: raise RuntimeError('production Lua candidate mismatch: '+name)
 listeners=ssh('netstat -lnt').stdout
 for port in (49543,49544,49545,49546,49547,49548,49549,49550,49556):
  if ':'+str(port)+' ' in listeners: raise RuntimeError('fixture listener conflict: '+str(port))
 ssh('umask 077; mkdir -p '+REMOTE)
 upload(root/'homepublish/tests/device-legacy-lua-scope.lua',REMOTE+'/device-legacy-lua-scope.lua')
 ssh("lua -e \"dofile('"+REMOTE+"/device-legacy-lua-scope.lua'); assert(package.loaded.homepublish_store==nil); print('LEGACY_LUA_ISOLATION_GREEN')\"")
 for src,dst in [('nginx','nginx-private'),('sslh-select','sslh-select.private')]:
  ssh('cp /usr/libexec/homepublish/'+src+' '+REMOTE+'/'+dst+' && chmod 0755 '+REMOTE+'/'+dst)
  assert ssh('sha256sum /usr/libexec/homepublish/'+src).stdout.split()[0]==ssh('sha256sum '+REMOTE+'/'+dst).stdout.split()[0]
 assert state==ssh('sha256sum /etc/homepublish/product/state').stdout.split()[0]
 print('LEGACY_LUA_PREFLIGHT_GREEN live_sha256='+state)
