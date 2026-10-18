const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const file=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish/overview.js');
test('LuCI dependency scan reaches api before the first ordinary string literal',async()=>{
 const source=fs.readFileSync(file,'utf8').replace(/\/\*[\s\S]*?\*\//g,'');
 const names=[],values=[];
 for(const m of source.matchAll(/(['"])(.*?)\1/g)){
  if(m[2]==='use strict')continue;
  const dep=/^require\s+(\S+)(?:\s+as\s+(\S+))?$/.exec(m[2]);
  if(!dep)break;
  names.push(dep[2]||dep[1].replace(/[^a-zA-Z0-9_]/g,'_'));
  values.push(dep[1]==='view'?{extend:o=>o}:dep[1]==='rpc'?{declare:()=>()=>Promise.resolve({})}:dep[2]==='api'?{status:()=>Promise.resolve({saved_revision:10}),checked:s=>s}:{});
 }
 assert.ok(names.includes('api'),'api dependency was skipped by the LuCI scanner');
 const view=new Function(...names,source)(...values);
 assert.deepEqual(await view.load(),{state:{saved_revision:10}});
});
