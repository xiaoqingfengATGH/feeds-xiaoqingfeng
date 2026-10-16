import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = new URL('../htdocs/luci-static/resources/view/homekms.js', import.meta.url);
function loadView() {
  const calls = [];
  let response = {};
  const context = {
    _: value => value,
    view: { extend: value => value },
    rpc: { declare: spec => (...args) => { calls.push({ spec, args }); return response instanceof Error ? Promise.reject(response) : Promise.resolve(response); } },
    E: (tag, attrs, children) => ({ tag, attrs, children, textContent: '', disabled: false }),
    form: {}, uci: {}, poll: {}, fs: {}, ui: {},
    console
  };
  const view = vm.runInNewContext('(function() {\n' + readFileSync(source, 'utf8') + '\n})()', context);
  return { view, calls, context, respond: value => { response = value; } };
}

test('package ACL permits only HomeKMS UCI writes and read-only status/logs; translations cover current UI', () => {
  const base = new URL('../', import.meta.url);
  const acl = JSON.parse(readFileSync(new URL('root/usr/share/rpcd/acl.d/luci-app-homekms.json', base), 'utf8'))['luci-app-homekms'];
  assert.deepEqual(acl.read, { uci: ['homekms'], ubus: { homekms: ['status', 'logs'] } });
  assert.deepEqual(acl.write, { uci: ['homekms'] });
  const menu = JSON.parse(readFileSync(new URL('root/usr/share/luci/menu.d/luci-app-homekms.json', base), 'utf8'));
  assert.equal(menu['admin/services/homekms'].action.path, 'homekms');
  assert.deepEqual(menu['admin/services/homekms'].depends.acl, ['luci-app-homekms']);
  const ids = [...new Set([...readFileSync(source, 'utf8').matchAll(/_\('([^']*)'\)/g)].map(m => m[1]).concat(Object.values(menu).map(m => m.title)))].sort();
  for (const path of ['po/zh_Hans/homekms.po', 'po/templates/homekms.pot']) {
    const data = readFileSync(new URL(path, base), 'utf8');
    assert.equal(data.replace(/\r\n/g, '').includes('\n'), false, 'catalogs preserve CRLF bytes');
    const entries = [...data.matchAll(/msgid ("[^\r\n]*")\r\nmsgstr ("[^\r\n]*")/g)].map(m => [JSON.parse(m[1]), JSON.parse(m[2])]).filter(entry => entry[0]);
    assert.deepEqual(entries.map(entry => entry[0]).sort(), ids);
    if (path.endsWith('.po')) assert.ok(entries.every(entry => entry[1].length));
  }
});

test('lifecycle actions and command execution dependencies are absent', () => {
  const h = loadView();
  assert.equal(h.view.runAction, undefined);
  assert.doesNotMatch(readFileSync(source, 'utf8'), /require (?:fs|ui)|fs\.exec|E\('button'/);
});

test('renders the named UCI form with safe defaults and polling updates status text', async () => {
  const h = loadView();
  const options = [];
  let map, section, polling;
  h.context.form.Map = class {
    constructor(...args) { map = args; }
    section(...args) { section = args; return { option: (type, name, ...labels) => { const o = { type, name, labels }; options.push(o); return o; } }; }
    render() { return Promise.resolve({ tag: 'form' }); }
  };
  Object.assign(h.context.form, { NamedSection: 'named', Flag: 'flag', Value: 'value', DummyValue: 'dummy' });
  h.context.uci.load = async name => { assert.equal(name, 'homekms'); };
  h.context.poll.add = (fn, interval) => { polling = { fn, interval }; };
  await h.view.load();
  const root = await h.view.render();
  assert.equal(map[0], 'homekms');
  assert.deepEqual(Array.from(section), ['named', 'main', 'homekms']);
  assert.deepEqual(options.map(o => o.name), ['enabled', '_status', '_listener', '_engine', 'port', 'auto_discovery', 'wan_access']);
  assert.equal(options.find(o => o.name === 'port').datatype, 'range(1024,65535)');
  assert.equal(options.find(o => o.name === 'port').default, '1688');
  const discovery = options.find(o => o.name === 'auto_discovery');
  assert.equal(discovery.type, 'flag');
  assert.equal(discovery.labels[0], 'DNS auto-discovery');
  assert.match(discovery.labels[1], /Disabled by default/);
  assert.match(discovery.labels[1], /Save & Apply/);
  assert.match(discovery.labels[1], /DNS SRV/);
  assert.match(discovery.labels[1], /local DNS domain/);
  assert.match(discovery.labels[1], /clients.*DNS server/);
  assert.match(discovery.labels[1], /stopped.*removed/);
  assert.match(discovery.labels[1], /system dnsmasq/);
  assert.match(discovery.labels[1], /DNS proxy or a separate DNS instance/);
  assert.match(discovery.labels[1], /refresh.*SRV record.*changes/);
  assert.match(discovery.labels[1], /Otherwise.*specify.*address and port manually/);
  assert.match(discovery.labels[1], /does not automatically refresh.*DNS services/);
  assert.equal(discovery.depends, undefined, 'keep the explicit off setting editable while service is disabled');
  for (const name of ['enabled', 'auto_discovery', 'wan_access']) {
    assert.equal(options.find(o => o.name === name).default, '0');
    assert.equal(options.find(o => o.name === name).rmempty, false);
  }
  assert.equal(root.tag, 'div');
  assert.equal(root.children[0].tag, 'form', 'native form precedes the trailing logs card');
  assert.equal(root.children.length, 2, 'no independent status card');
  assert.equal(root.children[1].children[0].children, 'Recent HomeKMS logs');
  assert.match(options[0].labels[1], /Save & Apply starts or stops/);
  for (const [name, node] of [['_status', h.view.statusNode], ['_listener', h.view.listenNode], ['_engine', h.view.engineNode]]) {
    const o = options.find(o => o.name === name);
    assert.equal(o.type, 'dummy');
    assert.equal(o.renderWidget(), node);
    assert.equal(o.renderWidget(), node, 'Save & Apply rerenders reuse the same polled span');
  }
  assert.equal(h.view.engineNode.children, 'py-kms 1.0.1 (embedded product database)');
  assert.equal(polling.interval, 5);
  h.respond({ running: true, checked: true, pid: 1234, port: 1688, listening: true });
  await polling.fn();
  assert.match(h.view.statusNode.textContent, /Running.*1234/);
  assert.match(h.view.listenNode.textContent, /Listening.*1688/);
  assert.equal(h.view.logNode.tag, 'pre');
  assert.ok(h.calls.some(call => call.spec.method === 'logs'), 'poll refreshes logs too');
  h.respond(new Error('denied'));
  await polling.fn();
  assert.equal(h.view.statusNode.textContent, 'Unavailable');
  h.respond({ running: false, checked: true, port: 1688, listening: false });
  await polling.fn();
  assert.equal(h.view.statusNode.textContent, 'Stopped');
});

test('status reads the checked PID-associated HomeKMS RPC snapshot', async () => {
  const h = loadView();
  h.respond({ running: true, checked: true, pid: 4321, port: 1688, listening: true });
  const status = await h.view.getStatus();
  assert.equal(status.state, 'running');
  assert.equal(status.pid, 4321);
  assert.equal(status.listening, true);
  assert.equal(status.port, 1688);
  assert.equal(h.calls[0].spec.object, 'homekms');
  assert.equal(h.calls[0].spec.method, 'status');
  assert.deepEqual(Array.from(h.calls[0].spec.params), []);
  assert.deepEqual(Array.from(h.calls[0].args), []);
  for (const reply of [{ running: false, checked: false }, {}, null, new Error('denied')]) {
    h.respond(reply);
    assert.equal((await h.view.getStatus()).state, 'unavailable');
  }
  h.respond({ running: false, checked: true, pid: null, port: 1688, listening: false });
  assert.equal((await h.view.getStatus()).state, 'stopped');
});

test('logs use parameterless bounded snapshot RPC and textContent, distinguish empty and unavailable', async () => {
  const h = loadView();
  const node = {};
  Object.defineProperty(node, 'innerHTML', { set() { throw new Error('unsafe HTML'); } });
  h.view.logNode = node;
  h.view.logNoticeNode = {};
  const text = 'homekms: <img src=x onerror=alert(1)>\n日志';
  h.respond({ text, available: true, truncated: true });
  await h.view.refreshLogs();
  assert.equal(node.textContent, text);
  assert.match(h.view.logNoticeNode.textContent, /truncated/);
  assert.equal(h.calls[0].spec.object, 'homekms');
  assert.equal(h.calls[0].spec.method, 'logs');
  assert.deepEqual(Array.from(h.calls[0].spec.params), []);
  assert.deepEqual(Array.from(h.calls[0].args), []);
  h.respond({ text: '', available: true, truncated: false });
  await h.view.refreshLogs();
  assert.equal(node.textContent, 'No HomeKMS log entries.');
  for (const reply of [{ text, available: false }, {}, new Error('denied')]) {
    h.respond(reply);
    await h.view.refreshLogs();
    assert.equal(node.textContent, 'Logs unavailable.');
    assert.equal(h.view.logNoticeNode.textContent, '');
  }
  assert.doesNotMatch(readFileSync(source, 'utf8'), /innerHTML/);
});

test('poll renders verified listening separately and clears stale state on unavailable', async () => {
  const h = loadView();
  h.view.statusNode = {};
  h.view.listenNode = {};
  h.view.logNode = {};
  h.view.logNoticeNode = {};
  h.respond({ running: true, checked: true, pid: 4321, port: 1688, listening: true });
  await h.view.refreshStatus();
  assert.match(h.view.listenNode.textContent, /Listening.*1688/);
  h.respond({ running: true, checked: true, pid: 4321, port: 1689, listening: false });
  await h.view.refreshStatus();
  assert.match(h.view.statusNode.textContent, /Running.*4321/);
  assert.match(h.view.listenNode.textContent, /Not listening.*1689/);
  h.respond({ running: false, checked: true, port: 1688, listening: false });
  await h.view.refreshStatus();
  assert.equal(h.view.statusNode.textContent, 'Stopped');
  h.respond({ running: false, checked: false, port: 1688, listening: false });
  await h.view.refreshStatus();
  assert.equal(h.view.statusNode.textContent, 'Unavailable');
  assert.equal(h.view.listenNode.textContent, 'Unavailable');
});
