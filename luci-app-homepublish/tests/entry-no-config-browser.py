# Run via browser_exec in an authenticated installed LuCI page:
# exec(pathlib.Path('D:/DevPortal/homelede/homepublish-product/luci-app-homepublish/tests/entry-no-config-browser.py').read_text())
# No Save/Start or fixture/bootstrap; only actual native select change events.
import json
import pathlib
import time

for _ in range(50):
    if js('!!document.getElementById("widget.cbid.json.cfg_listener.ipv4_address")'):
        break
    time.sleep(0.2)

snapshot_js = '''(() => {
 const fields=['family','ipv4_network','ipv4_address','ipv6_network','ipv6_address'];
 return {url:location.href,controls:fields.map(field=>{
  const nodes=document.querySelectorAll('[id="widget.cbid.json.cfg_listener.'+field+'"]');
  if(nodes.length!==1)throw Error(field+': expected one actual native control');
  const e=nodes[0];return {field,value:e.value,visible:!!e.getClientRects().length,
   options:Array.from(e.options).map(o=>({value:o.value,text:o.text}))};
 })};
})()'''

def snapshot():
    return js(snapshot_js)

def change(field,value):
    js('(() => {const e=document.getElementById('+json.dumps('widget.cbid.json.cfg_listener.'+field)+');e.value='+json.dumps(value)+';e.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(0.2)

results=[snapshot()]
for mode in ['ipv6','dual','ipv4']:
    change('family',mode)
    state=snapshot()
    controls={x['field']:x for x in state['controls']}
    for family,address in [('ipv4','192.168.1.2'),('ipv6','fd89:878e:a47f::1')]:
        control=controls[family+'_address']
        assert any(o['value']==address for o in control['options']), (mode,control)
        assert control['value']==address, (mode,control)
        assert control['visible']==(mode in [family,'dual']), (mode,control)
    results.append(state)
# Only capability-eligible networks are offered on untouched installed state.
change('family','dual')
for family in ['ipv4','ipv6']:
    state=snapshot()
    network=next(c for c in state['controls'] if c['field']==family+'_network')
    assert [o['value'] for o in network['options']]==['lan'], network
    addr=next(c for c in state['controls'] if c['field']==family+'_address')
    assert addr['options'] and all('已不可用' not in o['text'] for o in addr['options']), addr
results.append(snapshot())
path=pathlib.Path('D:/DevPortal/homelede/homepublish-product/docs/HOMEPUBLISH-TCP-P2-NOCONFIG-GREEN.json')
path.write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS installed no-config initial/family IPv4/IPv6/dual/network switching; no Save or Start')
print(json.dumps(results,ensure_ascii=False))
