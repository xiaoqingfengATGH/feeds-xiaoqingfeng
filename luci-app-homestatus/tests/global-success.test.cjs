const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
test('global luminous success tokens own all healthy dashboard text without app overrides',()=>{
 const root=process.env.HOMESTATUS_THEME;
 const css=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.css'),'utf8');
 assert.doesNotMatch(css,/body\[data-if-palette="luminousblue/,'application must not duplicate palette semantics');
 for(const [name,color] of [['luminousblue','#70d6b0'],['luminousblue-light','#16724f']]){
 const sheet=fs.readFileSync(path.join(root,'htdocs/luci-static/infinityfreedom-ng/assets/css/palette-'+name+'.min.css'),'utf8');
 assert.ok(sheet.includes('--bs-success:'+color+';'),name+' global success is not emerald');
 }
});
