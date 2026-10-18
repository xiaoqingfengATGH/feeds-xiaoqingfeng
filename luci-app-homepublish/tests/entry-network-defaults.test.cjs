const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish');
const api=new Function('baseclass','rpc','dom','ui',fs.readFileSync(path.join(dir,'product.js'),'utf8'))({extend:o=>o},{declare:()=>()=>{}},{},{});
test('both families default from wan-prefixed network membership, never zone existence or sibling',()=>{
 const saved={access_profile:{listeners:[]}};
 for(const [networks,expected] of [
  [[],['lan']],
  [[{network:'lan',zones:['lan'],up:true}],['lan']],
  [[{network:'wan',zones:['lan'],up:true}],['lan']],
  [[{network:'uplink',zones:['wan'],up:true}],['lan']],
  [[{network:'wan',zones:['wan'],up:true}],['wan']],
  [[{network:'wan6',zones:['wan'],up:false,addresses:[]}],['wan']],
  [[{network:'wan_backup',zones:['lan','wan'],up:false}],['wan']]
 ]){
  const row={family:'dual',ipv4_zones:[],ipv6_zones:[]};
  api.entryZoneDefaults(row,saved,['lan','wan'],networks);
  assert.deepEqual(row.ipv4_zones,expected,JSON.stringify(networks));assert.deepEqual(row.ipv6_zones,expected);
 }
 const row={family:'dual',ipv4_zones:['guest'],ipv6_zones:[]};
 api.entryZoneDefaults(row,saved,['lan','wan','guest'],[{network:'wan',zones:['wan']}]);
 assert.deepEqual(row.ipv6_zones,['wan']);
});
test('preserve explicit saved, disappeared, empty and inactive-family custom choices without mutation',()=>{
 for(const family of ['ipv4','ipv6'])for(const selected of [['wan'],['lan'],['custom'],['gone'],[],{}]){
  const saved={access_profile:{listeners:[{family,port:8443}],firewall:{[family+'_zones']:selected}}};
  const before=JSON.stringify(saved),row=api.entryDraft(saved);api.entryZoneDefaults(row,saved,['lan','wan'],[]);
  assert.deepEqual(row[family+'_zones'],api.zoneList(selected));assert.equal(JSON.stringify(saved),before);
 }
 const saved={access_profile:{listeners:[{family:'ipv4',port:8443}],firewall:{ipv4_zones:['lan'],ipv6_zones:['custom']}}};
 const row=api.entryDraft(saved);row.family='dual';api.entryZoneDefaults(row,saved,['lan','wan','custom'],[]);
 assert.deepEqual(row.ipv6_zones,['custom']);
});
test('missing preferred zone stays empty rather than selecting an unrelated zone',()=>{
 for(const zones of [[],['guest'],['wan']]){
  const row={family:'dual'};api.entryZoneDefaults(row,{},zones,[]);
  assert.deepEqual(row.ipv4_zones,[]);assert.deepEqual(row.ipv6_zones,[]);
 }
});
