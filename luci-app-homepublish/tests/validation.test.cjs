const {test}=require('node:test');const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const s=new Function('baseclass',fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish/schema.js'),'utf8'))({extend:v=>v});
const main={enabled:'1',exposure_approved:'1',ttl:'60',port:'18443',bind_port:'18444',stun_server:'stun.example',http_server:'example.com'};
const host={name:'a.example',upstream:'http://10.0.0.1:8080'};
test('enabled form requires integer ranges, numeric distinct ports, reviewed 1..16 unique services',()=>{
 assert.equal(typeof s.configuration,'function');assert.equal(s.configuration(main,[host]),true);
 for(const [key,value] of [['ttl','1.5'],['ttl','0'],['ttl','121'],['port','65536'],['bind_port','1023'],['bind_port','018443'],['exposure_approved','0']])assert.notEqual(s.configuration({...main,[key]:value},[host]),true,key+value);
 assert.equal(s.configuration({...main,bind_port:'018444'},[host]),true);
 for(const hosts of [[],Array(17).fill(host),[host,host]])assert.notEqual(s.configuration(main,hosts),true);
 assert.equal(s.configuration(main,Array.from({length:16},(_,i)=>({...host,name:`h${i}.example`}))),true);
});
test('disabled damaged configuration can be saved without repairing inactive fields',()=>{
 assert.equal(s.configuration({enabled:'0',ttl:'bad'},[{name:'INVALID',upstream:'bad'}]),true);
});
