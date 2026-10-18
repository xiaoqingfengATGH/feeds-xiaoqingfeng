"""Installed-source private save transport -> store -> live apply investigation.
Never saves production configuration, calls DDNS, or mutates firewall.
"""
import copy, hashlib, importlib.util, io, json, subprocess, tarfile, time
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('support',HERE/'run-device-upstream-tls-traffic.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
OUT=m.REPO/'docs/evidence/lua-store/backend-host-header-private-save-apply.json'
r=m.report

def main():
    before=m.baseline(); staged=False; lifecycle=False; error=None
    try:
        r['production_before']=json.loads(m.run('ubus call homepublish status'))
        r['production_runtime_before']=json.loads(m.service('list',{'name':'homepublish-runtime'}))
        r['production_nginx_before']=m.run('sha256sum /tmp/homepublish-runtime/nginx.conf; cat /tmp/homepublish-runtime/nginx.conf')
        p=subprocess.run(m.SSH+['tar -czf - -C /usr/share/homepublish .'],capture_output=True,check=True)
        with tarfile.open(fileobj=io.BytesIO(p.stdout),mode='r:gz') as t:
            blobs={Path(x.name).name:t.extractfile(x).read() for x in t.getmembers() if x.isfile() and x.name.endswith('.lua')}
        r['installed_source_sha256']={k:hashlib.sha256(v).hexdigest() for k,v in blobs.items()}
        orig=blobs['product-system-provider.lua'].decode()
        private=orig.replace("name='homepublish-runtime',root='/tmp/homepublish-runtime'",f"name='{m.NAME}',root='{m.RUNTIME}'").replace("firewall=require('product-firewall').new(),","firewall=nil, -- isolated; no production firewall writes")
        assert private!=orig and "root='/tmp/homepublish-runtime'" not in private
        blobs['product-system-provider.lua']=private.encode()
        blobs['product-store.lua']=f"return dofile('{m.ROOT}/source/product-store-core.lua').new('{m.ROOT}/store')\n".encode()
        cli=f"local source='{m.ROOT}/source';package.path=source..'/?.lua;'..package.path;local J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'));local q=J.decode(io.read('*a'));local r;if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='apply' then r=C.apply(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end;print(J.encode(r))"
        buf=io.BytesIO()
        with tarfile.open(fileobj=buf,mode='w:gz') as t:
            for name,data in [('source/'+k,v) for k,v in blobs.items()]+[('cli.lua',cli.encode())]:
                x=tarfile.TarInfo(name);x.size=len(data);x.mode=0o600;t.addfile(x,io.BytesIO(data))
        m.run('umask 077; mkdir '+m.ROOT+' && tar -xzf - -C '+m.ROOT,buf.getvalue());staged=True
        r['substitutions']=['fixed private store root','fixed private runtime root/procd name','firewall=nil; no production rule mutation','fixture services use manual DNS; no DDNS invocation']
        ports=json.loads(m.run("lua -e 'local n=require(\"nixio\");local a,s={},{};for i=1,2 do s[i]=assert(n.socket(\"inet\",\"stream\"));assert(s[i]:bind(\"0.0.0.0\",0));local _,p=s[i]:getsockname();a[i]=p end;print(require(\"luci.jsonc\").stringify(a))'"))
        shared,backend=ports;r['ports']={'shared':shared,'backend':backend}
        nginx='daemon off; master_process off; pid '+m.ROOT+'/backend.pid; error_log '+m.ROOT+'/backend.log; events {} http { access_log off; server { listen 0.0.0.0:'+str(backend)+' default_server; server_name _; location / { return 200 "DEFAULT|$http_host|$server_addr"; } } server { listen 0.0.0.0:'+str(backend)+'; server_name ai.iwonderful.top; location / { return 200 "NAMED|$http_host|$server_addr"; } } }'
        m.run('mkdir '+m.ROOT+'/logs; /usr/bin/tee '+m.ROOT+'/backend.conf >/dev/null',nginx.encode())
        m.service('set',{'name':m.NAME+'-backend','instances':{'web':{'command':['/usr/libexec/homepublish/nginx','-p',m.ROOT+'/','-c','backend.conf']}}});time.sleep(1)
        config={'schema_version':2,'access_profile':{'listeners':[{'listener_id':'private','family':'ipv4','network':'lan','address':'192.168.1.2','port':shared}]},'publication_policy':{'mode':'continuous','boot_restore':False},'services':[{'service_id':'svc_1','name':'VMWARE','enabled':True,'type':'http_proxy','hostname':'vmware.innonext.win','upstream_scheme':'http','dns':{'mode':'manual'},'backend':{'addressFamily':'ipv4','host':'127.0.0.1','port':backend}}]}
        # Exercise installed product-rpc.lua save JSON -> wire decode before provider save.
        def save(c,revision):
            request={'expected_revision':revision,'config':c}
            raw=m.run('lua '+m.ROOT+'/source/product-rpc.lua save',json.dumps(request).encode())
            decoder="local J=require('product-json');local W=require('product-wire');local P=require('product-provider');local q=W.decode(io.read('*a'));print(J.encode(assert(P.handle(q,true))))"
            response=json.loads(m.run('lua -e '+__import__('shlex').quote("package.path='"+m.ROOT+"/source/?.lua;'..package.path;"+decoder),raw.encode()))
            r.setdefault('save_requests',[]).append(request);r.setdefault('save_responses',[]).append(response)
            assert response['saved_config']['services'][0]['backend']==c['services'][0]['backend'],response
            return response
        s=save(config,0);lifecycle=True
        started=m.request({'action':'start','revision':s['saved_revision'],'approved':True});r['started']=started
        assert started['runtime']['phase']=='running',started
        curl="curl -q --noproxy '*' --fail --silent --show-error --max-time 8 -H 'Host: vmware.innonext.win' http://192.168.1.2:"+str(shared)+'/'
        r['traffic_before']=m.run(curl);assert r['traffic_before']=='DEFAULT|vmware.innonext.win|127.0.0.1'
        config=copy.deepcopy(config);config['services'][0]['backend'].update(host='192.168.1.2',host_header='ai.iwonderful.top')
        saved=save(config,s['saved_revision'])
        reread=m.request({'action':'status'});r['after_save_new_process']=reread
        assert reread['saved_config']['services'][0]['backend']==config['services'][0]['backend']
        assert reread['active_config']['services'][0]['backend']['host']=='127.0.0.1'
        r['traffic_saved_not_applied']=m.run(curl);assert r['traffic_saved_not_applied']==r['traffic_before']
        applied=m.request({'action':'apply','revision':saved['saved_revision'],'approved':True});r['applied']=applied
        assert applied['runtime']['phase']=='running',applied
        reread=m.request({'action':'status'});r['after_apply_new_process']=reread
        assert reread['active_revision']==saved['saved_revision']==reread['saved_revision']
        assert reread['active_config']['services'][0]['backend']==config['services'][0]['backend']
        rendered=m.run('cat '+m.RUNTIME+'/nginx.conf');r['rendered_after_apply']=rendered
        assert 'proxy_pass http://192.168.1.2:'+str(backend) in rendered and 'proxy_set_header Host ai.iwonderful.top;' in rendered
        r['traffic_after_apply']=m.run(curl);assert r['traffic_after_apply']=='NAMED|ai.iwonderful.top|192.168.1.2'
        r['runtime_readback']=json.loads(m.service('list',{'name':m.NAME}))
        capture=m.REPO/'docs/evidence/lua-store/backend-host-header-real-browser-capture.json'
        if capture.exists():
            actual=json.loads(capture.read_text(encoding='utf-8'))
            actual_request=next(x['params'] for x in actual['captures'] if x['method']=='save')
            r['browser_original_expected_revision']=actual_request['expected_revision']
            exact=save(actual_request['config'],saved['saved_revision'])
            exact_read=m.request({'action':'status'});r['exact_browser_payload_private_readback']=exact_read
            assert exact_read['saved_revision']==exact['saved_revision']
            assert exact_read['saved_config']['services'][0]['backend']==actual_request['config']['services'][0]['backend']
            assert exact_read['saved_config']==exact['saved_config']
            r['exact_browser_payload_persisted']=True
    except Exception as e:
        error=repr(e);r['error']=error
    finally:
        if lifecycle:
            try:
                r['stopped']=m.request({'action':'stop'});assert r['stopped']['runtime']['cleanup']=='confirmed'
            except Exception as e:r['cleanup_error']=repr(e)
        if staged:
            m.service('delete',{'name':m.NAME+'-backend'});time.sleep(2)
            r['cleanup_runtime']=json.loads(m.service('list',{'name':m.NAME}));r['cleanup_backend']=json.loads(m.service('list',{'name':m.NAME+'-backend'}))
            r['private_processes']=m.run("ps w | grep -E '"+m.ROOT+'|'+m.RUNTIME+"' | grep -v grep || true")
            if not r['cleanup_runtime'] and not r['cleanup_backend'] and not r['private_processes']:
                m.run('rm -rf '+m.ROOT+'; test ! -e '+m.ROOT+'; test ! -e '+m.RUNTIME);r['private_root_removed']=True
        r['production_after']=json.loads(m.run('ubus call homepublish status'))
        r['production_runtime_after']=json.loads(m.service('list',{'name':'homepublish-runtime'}))
        r['production_unchanged']=before==m.baseline()
        r['passed']=not error and not r.get('cleanup_error') and r['production_unchanged'] and r.get('private_root_removed',False)
        OUT.write_text(json.dumps(r,indent=2)+'\n')
    print(json.dumps({k:r.get(k) for k in ['passed','error','cleanup_error','traffic_before','traffic_saved_not_applied','traffic_after_apply','production_unchanged','private_root_removed']},indent=2))
    return 0 if r['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
