const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const app = process.env.HOMESTATUS_APP || path.resolve(__dirname, '..');
const theme = process.env.HOMESTATUS_THEME;
if (!theme) throw new Error('Set HOMESTATUS_THEME to the paired luci-theme-infinityfreedom-ng package directory (with baseline d0bddb3 in git history)');
const assets = 'htdocs/luci-static/resources/view/homestatus/';
test('compact LAN summary increments application release to four', () => {
 assert.match(fs.readFileSync(path.join(app, 'Makefile'), 'utf8'), /^PKG_RELEASE:=4$/m);
});
test('palette generator requires an explicit application stylesheet outside SDK', () => {
 const cp = require('node:child_process');
 const env = {...process.env}; delete env.HOMESTATUS_OVERVIEW_CSS;
 const result = cp.spawnSync('python', [path.join(theme, 'scripts/gen-palettes.py'), '--check'], {env, encoding:'utf8'});
 assert.notEqual(result.status, 0);
 assert.match(result.stderr + result.stdout, /Set HOMESTATUS_OVERVIEW_CSS to the application overview\.css/);
});
test('theme has no dashboard source duplicates and palette census reads app source', () => {
 assert.ok(!fs.existsSync(path.join(theme,'htdocs/luci-static/infinityfreedom-ng/assets/js/ngOverview.js')));
 assert.ok(!fs.existsSync(path.join(theme,'htdocs/luci-static/infinityfreedom-ng/assets/css/ngOverview.css')));
 const generator=fs.readFileSync(path.join(theme,'scripts/gen-palettes.py'),'utf8');
 assert.match(generator,/HOMESTATUS_OVERVIEW_CSS/);
 assert.match(generator,/overview_css\.read_text/);
 assert.match(fs.readFileSync(path.join(theme,'Makefile'),'utf8'),/\+luci-app-homestatus/);
 assert.match(fs.readFileSync(path.join(theme,'Makefile'),'utf8'),/HOMESTATUS_OVERVIEW_CSS=.*gen-palettes\.py/);
 assert.match(fs.readFileSync(path.join(app,'Makefile'),'utf8'),/\+luci-mod-status/);
});
test('overview assets are owned and loaded from application resources', () => {
 assert.ok(fs.existsSync(path.join(app, assets, 'overview.js')), 'application overview.js missing');
 assert.ok(fs.existsSync(path.join(app, assets, 'overview.css')), 'application overview.css missing');
 const footer = fs.readFileSync(path.join(theme, 'ucode/template/themes/infinityfreedom-ng/footer.ut'), 'utf8');
 assert.match(footer, /\{\{ resource \}\}\/view\/homestatus\/overview.js\?v=3/);
 assert.match(footer, /\{\{ resource \}\}\/view\/homestatus\/overview.css\?v=6/);
});
test('fallback stylesheet uses application resource and does not duplicate footer link', () => {
 const vm = require('node:vm');
 const code = fs.readFileSync(path.join(app, assets, 'overview.js'), 'utf8');
 for (const preloaded of [false, true]) {
  const links = preloaded ? [{href:'/luci-static/resources/view/homestatus/overview.css?v=1'}] : [];
  const document = {head:{appendChild:n=>links.push(n)}, addEventListener(){}, getElementById(){return null;}, querySelector(selector){return links.find(n=>selector.includes('overview.css') && n.href.includes('/view/homestatus/overview.css')) || null;}};
  vm.runInNewContext(code, {document, window:{location:{pathname:'/cgi-bin/luci/admin/status/overview'},setTimeout(){}}, L:{loaded:true,env:{},resource:p=>'/luci-static/resources/'+p}, E:(tag,attrs)=>attrs});
  assert.equal(links.length,1);
  assert.equal(links[0].href,'/luci-static/resources/view/homestatus/overview.css?v=6');
 }
});
