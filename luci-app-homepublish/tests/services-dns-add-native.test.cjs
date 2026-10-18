const fs=require('node:fs'),path=require('node:path');
let code=fs.readFileSync(path.join(__dirname,'services-dns-native.test.cjs'),'utf8');
code=code.replace("const start=code.indexOf", "code=code.replace(\"await page.getByRole('button',{name:'Edit',exact:true}).click()\",\"await page.getByRole('button',{name:'Add',exact:true}).click()\");\nconst start=code.indexOf");
code=code.replace("inputValue(),'manual'", "inputValue(),'ddns_go'");
const a=code.indexOf(" await field('hostname').fill"),b=code.indexOf(" assert.deepEqual(errors,[])",a);
code=code.slice(0,a)+" assert.deepEqual(errors,[]);console.log(JSON.stringify({newServiceDefaults:true,productionWrites:false}));\n"+code.slice(code.indexOf('`+code.slice(end);',b));
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
