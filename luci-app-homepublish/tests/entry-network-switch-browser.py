# Execute through browser_exec in authenticated official entry page. Never Save/Start.
import json
import pathlib
import time
import os
errors=[]
states=[]
def change(field,value):
    js('(() => {const e=document.getElementById('+json.dumps('widget.cbid.json.cfg_listener.'+field)+');e.value='+json.dumps(value)+';e.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(.15)
def snapshot(f,n):
    return js('''(() => {const f='''+json.dumps(f)+''', n='''+json.dumps(n)+''';const a=document.getElementById('widget.cbid.json.cfg_listener.'+f+'_address'),z=document.getElementById('cbid.json.cfg_listener.'+f+'_zone');return {family:f,network:n,value:a.value,disabled:a.disabled,invalid:a.classList.contains('cbi-input-invalid'),options:Array.from(a.options).map(o=>({value:o.value,text:o.text,disabled:o.disabled})),zone:z.parentElement.textContent.trim(),url:location.href};})()''')
change('family','dual')
for f,addr in [('ipv4','192.168.1.2'),('ipv6','fd89:878e:a47f::1')]:
    candidates=js('Array.from(document.getElementById('+json.dumps('widget.cbid.json.cfg_listener.'+f+'_network')+').options).map(o=>({value:o.value,text:o.text,disabled:o.disabled}))')
    states.append({'family':f,'networks':candidates})
    if [o['value'] for o in candidates if not o['disabled']]!=['lan']:errors.append([f,'only eligible LAN selectable',candidates])
    change(f+'_network','lan')
    s=snapshot(f,'lan');states.append(s)
    if [o['value'] for o in s['options']]!=[addr] or s['value']!=addr:errors.append([f,'family address candidates',s])
    if s['zone']!='lan':errors.append([f,'zone',s])
phase=globals().get('PHASE','RED')
path=pathlib.Path('D:/DevPortal/homelede/homepublish-product/docs/HOMEPUBLISH-TCP-P2-NETWORK-'+phase+'.json')
path.write_text(json.dumps({'states':states,'errors':errors},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'phase':phase,'checks':len(states),'errors':errors},ensure_ascii=False))
assert not errors, str(len(errors))+' network/address/zone failures; evidence: '+str(path)
