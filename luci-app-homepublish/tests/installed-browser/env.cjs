const path=require('node:path'),fs=require('node:fs');
function required(name){if(!process.env[name])throw Error(name+' is required; see README.md');return process.env[name];}
const device=required('HP_DEVICE_URL').replace(/\/$/,'');
const url=new URL(device);if(url.protocol!=='http:'||url.username||url.password)throw Error('Use an explicit HTTP device URL without credentials');
const evidence=path.resolve(required('HP_EVIDENCE_DIR'));fs.mkdirSync(evidence,{recursive:true});
module.exports={device,evidence,playwright:required('HP_PLAYWRIGHT'),key:required('HP_SSH_KEY'),target:process.env.HP_SSH_TARGET||'root@'+url.hostname,port:process.env.HP_SSH_PORT||'22',pins:require(path.resolve(process.env.HP_PIN_FILE||path.join(__dirname,'pinned-installed.json')))};
