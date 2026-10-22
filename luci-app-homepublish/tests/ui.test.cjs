const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const base=path.resolve(__dirname,'..');
const dir=path.join(base,'htdocs/luci-static/resources/view/homepublish');
const read=f=>fs.readFileSync(path.join(dir,f),'utf8');
const menu=JSON.parse(fs.readFileSync(path.join(base,'root/usr/share/luci/menu.d/luci-app-homepublish.json'),'utf8'));
test('r9 menu exposes four tabs: overview, services(form), entry, certificates',()=>{
 assert.deepEqual(Object.keys(menu).sort(),['admin/services/homepublish','admin/services/homepublish/certificates','admin/services/homepublish/entry','admin/services/homepublish/overview','admin/services/homepublish/services']);
 assert.equal(menu['admin/services/homepublish'].action.type,'firstchild');
 assert.equal(menu['admin/services/homepublish/overview'].action.path,'homepublish/overview');
 assert.equal(menu['admin/services/homepublish/services'].action.path,'homepublish/services');
 assert.equal(menu['admin/services/homepublish/entry'].action.path,'homepublish/entry');
 assert.equal(menu['admin/services/homepublish/certificates'].action.path,'homepublish/certificates');
});
test('services view is a form.Map GridSection over RPC saved_config, not hand-built DOM',()=>{
 const src=read('services.js');
 assert.match(src,/'require form'/);
 assert.match(src,/new form\.(JSON)?Map\(/);
 assert.match(src,/form\.GridSection/);
 assert.match(src,/form\.JSONMap/);
 /* P2: load = loadEditor + ddnsProfiles, not a raw api.status() call */
 assert.match(src,/api\.loadEditor\(false\)/);
 for(const opt of [/form\.Flag,\s*'enabled'/,/form\.Value,\s*'name'/,/form\.Value,\s*'hostname'[\s\S]*?datatype\s*=\s*'hostname'/,/form\.Value,\s*'backend_host'/,/form\.ListValue,\s*'certificate_ref'/])
  assert.match(src,opt);
 assert.match(src,/modalizable|modalonly/);
 assert.doesNotMatch(src,/hp-native|hp-tab-|hp-add-service|hp-edit-submit/,'no hand-built DOM form remains in services view');
 assert.doesNotMatch(src,/installed public provider unsupported/);
 assert.doesNotMatch(src,/!\s*cap\.start|!\s*cap\.apply/);
});
test('entry view is a form.Map NamedSection with listener, certificate and policy options',()=>{
 const src=read('entry.js');
 assert.match(src,/'require form'/);
 assert.match(src,/new form\.(JSON)?Map\(/);
 assert.match(src,/form\.NamedSection/);
 for(const opt of [/form\.Value,\s*'port','共享入口端口'[\s\S]*?datatype\s*=\s*'range\(1024,65535\)'/,/form\.ListValue,\s*'bind_mode'/,/form\.ListValue,\s*'default_certificate_ref'/,/mode[\s\S]*?continuous[\s\S]*?temporary/,/boot_restore/])
  assert.match(src,opt);
 assert.doesNotMatch(src,/hp-native|data-field=/);
 assert.doesNotMatch(src,/installed public provider unsupported/);
});
test('certificates view is a read-only inventory table from the certificates RPC',()=>{
 const src=read('certificates.js');
 assert.match(src,/api\.certificates\(\)/);
 assert.match(src,/read\s*=\s*true|readonly/);
 assert.doesNotMatch(src,/hp-native/);
 for(const heading of [/身份|证书/])
  assert.match(src,heading);
});
test('no view keeps synthetic provider-unsupported gating or cap.start/cap.apply disables',()=>{
 for(const f of fs.readdirSync(dir)){
  const src=read(f);
  assert.doesNotMatch(src,/installed public provider unsupported/,f);
  assert.doesNotMatch(src,/!\s*cap\.start/,f);
  assert.doesNotMatch(src,/!\s*cap\.apply/,f);
 }
});
test('old settings.js route is replaced by the services form view',()=>{
 assert.notEqual(menu['admin/services/homepublish/services'].action.path,'homepublish/settings');
});
test('ACL still ubus-only: read status/validate/certificates, write save/stop/start/apply',()=>{
 const acl=JSON.parse(fs.readFileSync(path.join(base,'root/usr/share/rpcd/acl.d/luci-app-homepublish.json'),'utf8'))['luci-app-homepublish'];
 assert.deepEqual(acl.read,{ubus:{homepublish:['ddns_profiles','probe','status','validate','certificates','network_inventory','preflight','migration_preview']}});
 assert.deepEqual(acl.write,{ubus:{homepublish:['save','stop','start','apply']}});
});
test('provider reports real installed capabilities without synthetic unsupported gating',()=>{
 const src=fs.readFileSync(path.join(base,'../homepublish/files/usr/share/homepublish/product-provider.lua'),'utf8');
 assert.match(src,/out\.capabilities=\{start=supported,apply=supported,stop=true/);
 assert.doesNotMatch(src,/installed public provider unsupported/);
});
