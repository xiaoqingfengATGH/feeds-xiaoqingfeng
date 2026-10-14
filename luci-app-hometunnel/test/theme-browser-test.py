"""Real Edge regression: actual HomeTunnel views + pinned theme CSS, no network/RPC.
python test/theme-browser-test.py --theme D:/.../luci-theme-infinityfreedom --out C:/.../scratch/evidence
Native OS popup option rendering is NOT asserted by computed styles.
"""
import argparse, hashlib, html, json, os, pathlib, re, subprocess, sys
p = argparse.ArgumentParser()
p.add_argument('--theme', required=True)
p.add_argument('--out', required=True)
p.add_argument('--no-theme', action='store_true')
p.add_argument('--slice', choices=['select', 'wizard', 'banner', 'shared', 'all'], default='all')
p.add_argument('--edge', default='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe')
a = p.parse_args()
app = pathlib.Path(__file__).resolve().parents[1] / 'htdocs/luci-static/resources/view/hometunnel'
css = pathlib.Path(a.theme) / 'luci-theme-infinityfreedom-ng/htdocs/luci-static/infinityfreedom-ng/assets/css'
out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
names = ['default', 'blackgold', 'canyon', 'luminousblue', 'luminousblue-light']
base = ['bootstrap.min.css', 'app.min.css', 'bootstrap-dark.min.css', 'app-dark.min.css']
js = r'''
const E=(tag,attrs={},children=[])=>{const e=document.createElement(tag);Object.entries(attrs).forEach(([k,v])=>e.setAttribute(k,v));(Array.isArray(children)?children:[children]).forEach(c=>{if(c!=null)e.append(c instanceof Node?c:document.createTextNode(c))});return e};
const _=x=>x, baseclass={extend:x=>x},view={extend:x=>x};
const htui=new Function('baseclass',SRC.ui)(baseclass);
const form={Flag:'flag',Value:'value',ListValue:'list',NamedSection:'section',Map:class {
 constructor(){this.root=E('div',{'class':'cbi-map'})}
 section(){return {option:(type,key,label)=>{const o={value:(value,text)=>o.sel.append(E('option',{value},text))};if(type==='list'){o.sel=E('select',{'class':'cbi-input-select',id:key});this.root.append(E('div',{'class':'cbi-value-field'},o.sel))}return o}}}
 render(){return Promise.resolve(this.root)}
}};
const uci={get:()=>'',sections:()=>[]}, L={bind:(f,s)=>f.bind(s),url:()=>'/fixture',resolveDefault:(p,d)=>p.catch(()=>d)};
const calls=[];const fs={exec:async(...x)=>{calls.push(x);return {code:0,stdout:''}},read:async()=>'',read_direct:async()=>'',stat:async()=>({size:0})};
const rpc={declare:()=>async()=>({})},poll={add:()=>{throw Error('unexpected poll')}};
const settings=new Function('form','view','htui','_',SRC.settings)(form,view,htui,_);
const wizard=new Function('view','htui','_','E','uci','L','fs',SRC.wizard)(view,htui,_,E,uci,L,fs);
const status=new Function('view','htui','_','E','uci','L','fs','rpc','poll',SRC.status)(view,htui,_,E,uci,L,fs,rpc,poll);
const diagram=new Function('view','htui','_','E','uci','L',SRC.diagram)(view,htui,_,E,uci,L);
function snap(e){const s=getComputedStyle(e);return {text:e.textContent,color:s.color,bg:s.backgroundColor,image:s.backgroundImage,border:s.borderColor,outline:s.outline,shadow:s.boxShadow,inline:e.getAttribute('style'),cls:e.className}}
function switchTo(n){document.body.dataset.ifPalette=n;document.querySelectorAll('style[data-palette]').forEach(s=>s.disabled=s.dataset.palette!==n)}
function rows(){const result=[];
 document.querySelectorAll('select').forEach((e,i)=>result.push({key:'select/'+i,...snap(e)}));
 document.querySelectorAll('[data-step]').forEach(bar=>{[...bar.querySelectorAll('.ht-step,span[style*="border-radius:999px"]')].forEach((e,i)=>result.push({key:'wizard/'+bar.dataset.step+'/'+i,...snap(e)}))});
 document.querySelectorAll('[data-banner]').forEach(e=>result.push({key:'banner/'+e.dataset.banner,...snap(e)}));
 document.querySelectorAll('[data-shared]').forEach(e=>result.push({key:'shared/'+e.dataset.shared,...snap(e)}));return result}
(async()=>{
 const root=await settings.render();document.querySelector('#view').append(root);
 root.querySelectorAll('select').forEach(e=>e.classList.add('form-select'));
 const originalStep3=wizard.step3;
 for(let step=1;step<=6;step++){
  wizard.getStep=()=>step;wizard.bound=false;
  for(let i=1;i<=6;i++)wizard['step'+i]=()=>{};
  if(step===3)wizard.step3=originalStep3;
  const w=wizard.renderInner();document.querySelector('#view').append(w);
  w.querySelector('.ht-info-banner').dataset.banner='wizard-'+step;w.querySelector('.ht-stepbar').dataset.step=step;
 }
 for(const [name,mod] of [['status',status],['diagram',diagram]]){
  const r=await mod.render();document.querySelector('#view').append(r);r.children[1].dataset.banner=name;
 }
 // Populate the actual step3 control as a successful zones result, without RPC.
 const domain=document.querySelector('[data-step="3"]').parentNode.querySelector('select');
 domain.append(E('option',{value:'example.org'},'example.org (active)'));domain.style.display='';
 const shared=htui.apply(E('div'));
 for(const [i,cls] of ['alert-message','alert-message warning','alert-message success','alert-message error','label','label success','btn cbi-button','btn cbi-button cbi-button-apply','btn cbi-button cbi-button-save','btn cbi-button cbi-button-add','btn cbi-button cbi-button-reset','btn cbi-button cbi-button-negative'].entries())shared.append(E('div',{'class':cls,'data-shared':i},'Safe fixture'));
 shared.append(E('pre',{'data-shared':'pre'},'Safe fixture output'));document.querySelector('#view').append(shared);
 await new Promise(r=>setTimeout(r,350));
 const before=rows(), focus=[];
 for(const [i,e] of [...document.querySelectorAll('select')].entries()){e.focus();await new Promise(r=>setTimeout(r,200));focus.push({key:'select/'+i,focused:e.matches(':focus'),...snap(e)});e.blur()}
 const target=NAME==='luminousblue-light'?'blackgold':'luminousblue-light';switchTo(target);
 await new Promise(r=>setTimeout(r,200));const switched=rows();switchTo(NAME);
 await new Promise(r=>setTimeout(r,200));const reverted=rows();
 document.body.append(E('pre',{id:'evidence'},JSON.stringify({palette:NAME,target,before,focus,switched,reverted,calls})));
})().catch(e=>document.body.append(E('pre',{id:'error'},e.stack)));
'''
def rgb(s):
    return [float(x)/255 for x in re.findall(r'[\d.]+', s)[:3]]
def contrast(x,y):
    def lum(v):
        return sum(z*w for z,w in zip([n/12.92 if n<=.04045 else ((n+.055)/1.055)**2.4 for n in rgb(v)], [.2126,.7152,.0722]))
    l,h=sorted([lum(x),lum(y)]);return (h+.05)/(l+.05)
results=[]; failures=[]; checks=0
sources={n:(app/(n+'.js')).read_text(encoding='utf-8') for n in ['ui','settings','wizard','status','diagram']}
styles=''.join('<style>'+ (css/f).read_text(encoding='utf-8')+'</style>' for f in base)
styles+=''.join('<style data-palette="'+n+'" '+('disabled' if n!='default' else '')+'>'+ (css/('palette-'+n+'.min.css')).read_text(encoding='utf-8')+'</style>' for n in names[1:])
styles+='<style>'+ (css/'ng.css').read_text(encoding='utf-8')+'</style>'
if a.no_theme:
    styles='';names=['unthemed']
for name in names:
    page=out/(name+'.html')
    page.write_text('<!doctype html><html><head>'+styles+'</head><body data-if-palette="'+name+'"><main id="view"></main><script>const SRC='+json.dumps(sources)+';const NAME='+json.dumps(name)+';'+js.replace('(async()=>{','switchTo(NAME);(async()=>{')+'</script></body></html>',encoding='utf-8')
    proc=subprocess.run([a.edge,'--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--user-data-dir='+str(out/('edge-'+name)),'--dump-dom','--virtual-time-budget=4000',page.as_uri()],capture_output=True,timeout=45)
    dom=proc.stdout.decode('utf-8',errors='replace'); m=re.search(r'<pre id="evidence">(.*?)</pre>',dom,re.S)
    if not m:
        (out/(name+'-error.txt')).write_text(dom+'\n'+proc.stderr.decode('utf-8',errors='replace'),encoding='utf-8');raise RuntimeError(name+' missing browser evidence')
    data=json.loads(html.unescape(m[1]));results.append(data)
    for phase in ['before','switched','reverted']:
        for row in data[phase]:
            family=row['key'].split('/')[0]
            if a.slice!='all' and family!=a.slice:continue
            checks+=1
            row['contrast']=round(contrast(row['color'],row['bg']),3)
            # Old gradients/transparent backgrounds also fail the owned-pair contract.
            if row['image']!='none' or row['bg'].startswith('rgba(') or row['contrast']<4.5:
                failures.append({'palette':name,'phase':phase,'key':row['key'],'reason':'owned opaque AA pair','contrast':row['contrast'],'bg':row['bg'],'color':row['color'],'image':row['image']})
    if a.slice in ['all','select']:
        for row in data['focus']:
            checks+=1
            ring=re.search(r'rgb\([^)]+\)',row['outline'])
            if not row['focused'] or not ring or contrast(row['color'],row['bg'])<4.5 or contrast(ring.group(),row['bg'])<3:failures.append({'palette':name,'key':row['key'],'reason':'focus pair/ring contrast >=3'})
    if [(r['key'],r['color'],r['bg'],r['image']) for r in data['before']]!=[(r['key'],r['color'],r['bg'],r['image']) for r in data['reverted']]:
        # Compare stable palette pairs; theme border transitions are separate focus evidence.
        failures.append({'palette':name,'reason':'palette revert mismatch'})
    if len(data['before'])!=60:failures.append({'palette':name,'reason':'expected 3 selects + 36 pills + 8 banners + 13 shared roles','actual':len(data['before'])})
    if data['calls']!=[['/usr/share/hometunnel/hometunnel.sh',['status']]]:failures.append({'palette':name,'reason':'unexpected fixture RPC','calls':data['calls']})
(out/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
summary={'palettes':len(results),'slice':a.slice,'checks':checks,'failures':failures,'source_sha256':{str(app/(n+'.js')):hashlib.sha256((app/(n+'.js')).read_bytes()).hexdigest() for n in sources},'native_option_popup':'not visually validated','browser':'real headless Microsoft Edge','theme_css_sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in css.glob('*.css') if f.name in base+['ng.css']+['palette-'+n+'.min.css' for n in names[1:]]}}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'palettes':len(results),'slice':a.slice,'checks':checks,'failures':len(failures),'first_failures':failures[:5],'evidence':str(out)},ensure_ascii=False))
sys.exit(bool(failures))
