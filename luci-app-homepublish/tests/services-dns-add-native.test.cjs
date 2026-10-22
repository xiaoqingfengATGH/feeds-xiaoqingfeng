
/* REQ-012 prerequisite guard: this file is a real-device/browser acceptance
 * script, not a self-contained unit test. When the device LuCI (HP_DEVICE_URL,
 * default http://192.168.1.2) or the local playwright install is unreachable,
 * skip gracefully so `node --test` stays green offline. */
{
 const device=(process.env.HP_DEVICE_URL||'http://192.168.1.2').replace(/\/$/,'');
 const pw=process.env.HP_PLAYWRIGHT||process.env.LOCALAPPDATA+'/hermes/cache/scratch/hp-p2-browser-deps/node_modules/playwright';
 let ok=true;
 try{require.resolve(pw);}catch(e){ok=false;}
 if(ok){try{require('node:child_process').execSync('curl -s -m 2 -o /dev/null '+device,{stdio:'ignore'});}catch(e){ok=false;}}
 if(!ok){console.log('SKIP: device LuCI ('+device+') or playwright ('+pw+') unavailable; this is a real-device acceptance script.');process.exit(0);}
}
const fs=require('node:fs'),path=require('node:path');
let code=fs.readFileSync(path.join(__dirname,'services-dns-native.test.cjs'),'utf8');
code=code.replace("const start=code.indexOf", "code=code.replace(\"await page.getByRole('button',{name:'Edit',exact:true}).click()\",\"await page.getByRole('button',{name:'Add',exact:true}).click()\");\nconst start=code.indexOf");
code=code.replace("inputValue(),'manual'", "inputValue(),'ddns_go'");
const a=code.indexOf(" await field('hostname').fill"),b=code.indexOf(" assert.deepEqual(errors,[])",a);
code=code.slice(0,a)+" assert.deepEqual(errors,[]);console.log(JSON.stringify({newServiceDefaults:true,productionWrites:false}));\n"+code.slice(code.indexOf('`+code.slice(end);',b));
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
