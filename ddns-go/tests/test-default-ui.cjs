// Host regression: shipped UCI default and LuCI option declaration.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const pkg = path.resolve(__dirname, '..');
const ui = process.argv[2] || path.resolve(pkg, '../luci-app-ddns-go/htdocs/luci-static/resources/view/ddns-go.js');
const tests = [];
function test(name, fn) { try { fn(); console.log('PASS ' + name); } catch (e) { tests.push(name); console.error('FAIL ' + name + ': ' + e.message); } }
test('packaged local API defaults on; main service default remains unchanged', () => {
  const conf = fs.readFileSync(path.join(pkg, 'files/ddns-go.conf'), 'utf8');
  assert.match(conf, /option local_api '1'/);
  assert.match(conf, /option enabled '0'/);
});
test('LuCI exposes default-on switch with exact Chinese help and explicit off persistence', () => {
  const options = [];
  const section = {option(type, key, title, description) {const o = {key, title, description, enabled:'1', disabled:'0'}; options.push(o); return o;}};
  const form = {Map: class {section() {return {...section};} render() {return options;}}, Flag: {}, Value: {}, TypedSection: {}, NamedSection: {}};
  const source = fs.readFileSync(ui, 'utf8');
  const page = new Function('form', 'poll', 'rpc', 'uci', 'view', '_', source)(form, {}, {declare(){return ()=>{};}}, {get(){}}, {extend(x){return x;}}, x=>x);
  page.render(['ddns-go']);
  const option = options.find(o=>o.key==='local_api');
  assert.ok(option, 'missing local_api flag');
  assert.equal(option.title, '允许本机应用联动');
  assert.equal(option.description, '允许 HomePublish 等本机应用读取域名配置并请求维护解析记录。');
  assert.equal(option.default, '1');
  assert.equal(option.rmempty, false);
});
if (tests.length) process.exitCode = 1;
