#!/usr/bin/env python
"""Isolated real-router listener acceptance; never touches production config/nft.

Copies current Lua modules into a unique /tmp/homepublish-portcheck-* tree and
uses only its own procd service. Run after implementation with --enforce. Without
--enforce, captures baseline failures without pretending product acceptance.
The group integration contract is documented in PORT-CHECK-ACCEPTANCE.md.
"""
import argparse
import base64
import io
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
REMOTE = r'''
import base64, io, json, os, pathlib, shutil, socket, subprocess, tarfile, time, uuid
root = pathlib.Path('/tmp/homepublish-portcheck-' + uuid.uuid4().hex[:12])
root.mkdir(mode=0o700)
with tarfile.open(fileobj=io.BytesIO(base64.b64decode(PAYLOAD)), mode='r:gz') as t:
    t.extractall(root)
modules = root / 'modules'
results=[]

def command(args, **kw):
    return subprocess.run(args, text=True, capture_output=True, **kw)
def snapshot():
    p=command(['ubus','call','service','list',json.dumps({'name':'homepublish-runtime'})])
    return json.loads(p.stdout)
def listening(port):
    rows=[]
    for family in ('tcp','tcp6'):
        for line in pathlib.Path('/proc/net/'+family).read_text().splitlines()[1:]:
            x=line.split()
            if int(x[1].split(':')[1],16)==port and x[3]=='0A':
                rows.append({'family':family,'local':x[1],'inode':x[9]})
    return rows

def reserve(address='127.0.0.1'):
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.bind((address,0));s.listen(8)
    return s

baseline=snapshot()
try:
    for kind in ('correct','wrong-socket','foreign-correct-own-wrong','occupied-shared','occupied-dedicated','different-address'):
        holder=reserve(); expected=holder.getsockname()[1]
        spare=reserve(); actual=spare.getsockname()[1];spare.close()
        # Positive and wrong-socket cases release the intended port first.
        if kind in ('correct','wrong-socket'):
            holder.close(); holder=None
        bind='127.0.0.1'; bound=expected if kind in ('correct','occupied-shared','occupied-dedicated') else actual
        if kind=='different-address':
            bind='127.0.0.2';bound=expected
        name='homepublish-portcheck-'+uuid.uuid4().hex[:10]
        runtime=str(root/name)
        config='daemon off; master_process on; error_log stderr notice; pid '+runtime+'/nginx.pid; events {} http { access_log off; server { listen '+bind+':'+str(bound)+'; return 200; } }'
        listener={'listener_id':'public4','family':'ipv4','network':'','bind_mode':'auto' if kind.startswith('occupied') else 'address','address':'0.0.0.0' if kind.startswith('occupied') else '127.0.0.1','port':expected}
        service={'service_id':'probe','type':'https_proxy','enabled':True}
        if kind=='occupied-dedicated':
            listener['port']=actual
            service={'service_id':'probe','type':'tcp_forward','enabled':True,'listen_port':expected}
        plan={'configuration':config,'listeners':[listener],'services':[service], 'snapshots':[]}
        # JSON transported as Lua long-string, never interpolated untrusted paths.
        lua="package.path="+json.dumps(str(modules)+'/?.lua;')+"..package.path\nlocal J=require('product-json');local options={name="+json.dumps(name)+",root="+json.dumps(runtime)+",nginx='/usr/libexec/homepublish/nginx',sslh='/usr/libexec/homepublish/sslh-select'};local Factory=require('product-procd-group');local G=Factory.new(options)\nlocal p=J.decode([==["+json.dumps(plan)+"]==]);local ok,e=G.start(p,1);os.execute('sleep 1');local healthy,he=G.healthy();local checked,ce;local lok,L=pcall(require,'product-listeners');if lok then local f=io.popen('ubus call service list '..string.format('%q',J.encode({name="+json.dumps(name)+"})));local state=J.decode(f:read('*a'));f:close();local v=state["+json.dumps(name)+"];if v and v.instances.nginx.pid then local owners=L.family({nginx=v.instances.nginx.pid});local rows=L.rows();checked,ce=L.verify({{component='nginx',address='127.0.0.1',family='ipv4',port="+str(expected)+",label='acceptance intended socket'}},rows,owners) end end;local recovered,re;if ok then local f=assert(io.open(options.root..'/listeners.json','w'));f:write(J.encode({{component='nginx',address='127.0.0.1',family='ipv4',port="+str(expected)+",label='acceptance intended socket'}}));f:close();recovered,re=Factory.new(options).healthy() end;local stopped=G.stop();print('PORTCHECK '..J.encode({recovered_healthy=recovered==true,recovered_error=tostring(re),checked_listener=checked==true,check_error=tostring(ce),started=ok==true,error=tostring(e),healthy=healthy==true,health_error=tostring(he),stopped=stopped==true}))\n"
        before=listening(expected)
        try:
            p=command(['lua','-'], input=lua, timeout=35)
            lines=[x[len('PORTCHECK '):] for x in p.stdout.splitlines() if x.startswith('PORTCHECK ')]
            observed=json.loads(lines[-1]) if lines else {'runner_error':p.stderr,'returncode':p.returncode}
        finally:
            # Delete only the unique owned service; never invoke global init scripts.
            command(['ubus','call','service','delete',json.dumps({'name':name})])
            time.sleep(.25)
        for _ in range(50):
            after=listening(expected)
            actual_after=listening(actual)
            if after==before and not actual_after: break
            time.sleep(.1)
        absent=name not in json.loads(command(['ubus','call','service','list',json.dumps({'name':name})]).stdout)
        if kind=='correct':
            accepted=observed.get('started') is True and observed.get('healthy') is True and observed.get('checked_listener') is True
        elif kind in ('occupied-shared','occupied-dedicated'):
            accepted=observed.get('started') is False and 'address in use' in observed.get('error','')
        else:
            accepted=observed.get('started') is True and observed.get('checked_listener') is False and observed.get('check_error') not in (None,'nil') and observed.get('recovered_healthy') is False and observed.get('recovered_error') not in (None,'nil')
        cleaned=observed.get('stopped') is True and absent and after==before and not actual_after
        results.append({'case':kind,'expected_port':expected,'actual_port':bound,'observed':observed,'product_pass':accepted,'cleanup_pass':cleaned,'before':before,'after':after,'actual_after':actual_after})
        if holder: holder.close()
    unchanged=snapshot()==baseline
    print(json.dumps({'root':str(root),'results':results,'production_service_unchanged':unchanged,'passed':unchanged and all(x['product_pass'] and x['cleanup_pass'] for x in results)},indent=2))
finally:
    # Only remove private files after every private service is absent.
    remaining=json.loads(command(['ubus','call','service','list']).stdout)
    ours=[n for n in remaining if n.startswith('homepublish-portcheck-')]
    if not ours: shutil.rmtree(root)
'''


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--host', default='192.168.1.2')
    p.add_argument('--key', default='D:/DevPortal/CloudHosts/HomePri.key')
    p.add_argument('--evidence', type=Path, required=True)
    p.add_argument('--enforce', action='store_true')
    a=p.parse_args()
    buf=io.BytesIO()
    with tarfile.open(fileobj=buf,mode='w:gz') as t:
        for source in sorted((ROOT/'files/usr/share/homepublish').glob('*.lua')):
            t.add(source,arcname='modules/'+source.name)
    program='PAYLOAD='+repr(base64.b64encode(buf.getvalue()).decode())+'\n'+REMOTE
    cmd=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ProxyCommand=none','-o','ProxyJump=none','-i',a.key,'-p','22','root@'+a.host,'python3 -']
    r=subprocess.run(cmd,input=program.encode(),capture_output=True,timeout=250)
    a.evidence.parent.mkdir(parents=True,exist_ok=True)
    a.evidence.write_bytes(r.stdout)
    if r.stderr: print(r.stderr.decode(errors='replace'))
    print(r.stdout.decode(errors='replace'))
    if r.returncode: raise SystemExit(r.returncode)
    data=json.loads(r.stdout)
    if a.enforce and not data['passed']: raise SystemExit(1)

if __name__=='__main__': main()
