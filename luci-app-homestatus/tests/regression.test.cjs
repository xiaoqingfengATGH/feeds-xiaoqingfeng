const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const cp=require('node:child_process');
const path=require('node:path');
const theme=process.env.HOMESTATUS_THEME;
if (!theme) throw new Error('Set HOMESTATUS_THEME to the paired luci-theme-infinityfreedom-ng package directory (with baseline d0bddb3 in git history)');
const app=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.js'),'utf8');
const baseline=cp.execFileSync('git',['show','d0bddb3:luci-theme-infinityfreedom-ng/htdocs/luci-static/infinityfreedom-ng/assets/js/ngOverview.js'],{cwd:path.dirname(theme),encoding:'utf8'});
function exportsOf(code){const context={window:{location:{pathname:'/admin/status/overview'}},result:null}; const hook='\n globalThis.result={normalize,health,diskRows,overlayRow,collectExisting,pruneDrawer}; return;\n';vm.runInNewContext(code.replace('\t/* ------------------------------------------------------------- boot ----- */',hook+'\t/* ------------------------------------------------------------- boot ----- */'),context);return context.result;}
const old=exportsOf(baseline), current=exportsOf(app);
const plain=x=>JSON.parse(JSON.stringify(x));
test('outside explicit LAN presentation changes, data/actions/polling/classic drawer remain baseline-identical',()=>{
 const body=s=>{
  s=s.slice(s.indexOf('(function()'),s.indexOf('\tfunction attachCss()')).split(String.fromCharCode(13)).join('');
  // Only the LAN presentation region and old equal-height cap are authorized.
  const start=s.includes('\t/* LAN presentation only:')?'\t/* LAN presentation only:':'\tfunction renderDevices(d)';
  const end='\t/* Side-router variant of the WAN card:';
  assert.ok(s.includes(start)&&s.includes(end));
  s=s.slice(0,s.indexOf(start))+'/* LAN presentation */\n\n'+s.slice(s.indexOf(end));
  s=s.replace('\t\t\t\t\t/* Detail-only addresses; never alter normalized online/count semantics. */\n\t\t\t\t\tstate.deviceHints = v[7] || {};\n','');
  s=s.replace('\tfunction render(d) {\n\t\tstate.lastNorm = d;\n\t\tupdateDevicePanel(d);','\tfunction render(d) {');
  s=s.replace("\t\tvar internetCard = inetKpi(d);\n\t\tinternetCard.classList.add('ngov-kpi-internet');\n\t\tcards.push(internetCard);",'\t\tcards.push(inetKpi(d));');
  const cap=s.indexOf('\t\t/* Equal heights:');
  if(cap>=0)s=s.slice(0,cap)+s.slice(s.indexOf('\t\t/* The two optional blocks.',cap));
  return s;
 };
 assert.equal(body(app),body(baseline));
});
test('normalization and health parity for WAN, side router, toggles, readonly disks and disabled services',()=>{
 const lan={interface:'lan',up:true,device:'br-lan','ipv4-address':[{address:'192.168.1.1',mask:24}],route:[{target:'0.0.0.0',mask:0,nexthop:'192.168.1.254'}]};
 const wan={interface:'wan',up:true,device:'eth1','ipv4-address':[{address:'10.0.0.2',mask:24}]};
 const disk={partitions:[{name:'sda1',fstype:'squashfs',readonly:true,mounts:[{target:'/rom',use_pct:100}]},{name:'sda2',volumes:[{name:'loop0',fstype:'f2fs',mounts:[{target:'/rom/overlay',use_pct:20}]}]}]};
 for(const raw of [{},{ifaces:[lan]},{ifaces:[lan,wan]},{ifaces:[lan,wan,{interface:'wan6',proto:'dhcpv6',up:false}]},{ifaces:[lan,wan],hs:{disks:[disk],apps:[{state:'disabled'},{state:'stopped',critical:false}],config:{show_apps:false,show_storage:false}}}]){
  const n=current.normalize(raw), b=old.normalize(raw);
  assert.deepEqual(plain(n),plain(b));assert.deepEqual(plain(current.health(n)),plain(old.health(b)));
 }
 const n=current.normalize({ifaces:[lan,wan],hs:{disks:[disk],apps:[{state:'disabled'}]}});
 assert.equal(n.overlay.target,'/rom/overlay');assert.equal(current.health(n).level,'ok');assert.equal(n.hasWifi,false);
});
test('non-overview route exits before touching DOM or loading RPC',()=>{
 vm.runInNewContext(app,{window:{location:{pathname:'/admin/network/network'}}});
});
test('CSS outside the LAN detail region and authorized natural grid stretch remains baseline-identical',()=>{
 let css=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.css'),'utf8');
 css=css.replace(/\r/g,'').replace(/\n\n\/\* Internet connectivity:[\s\S]*?\/\* End Internet connectivity\. \*\//,'');
 const start=css.indexOf('/* LAN detail portal:');const end=css.indexOf('/* --------------------------------------------------------- responsiveness -- */',start);
 assert.ok(start>=0&&end>start);css=css.slice(0,start)+css.slice(end);
 const oldCss=cp.execFileSync('git',['show','d0bddb3:luci-theme-infinityfreedom-ng/htdocs/luci-static/infinityfreedom-ng/assets/css/ngOverview.css'],{cwd:path.dirname(theme),encoding:'utf8'});
 const stretched='.ngov-cols { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; align-items: stretch; }';
 assert.ok(css.includes(stretched),'Same-row cards must stretch naturally, without fixed heights');
 css=css.replace(stretched,stretched.replace('align-items: stretch','align-items: start'));
 const clean=s=>s.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\r/g,'');assert.equal(clean(css),clean(oldCss));
});
