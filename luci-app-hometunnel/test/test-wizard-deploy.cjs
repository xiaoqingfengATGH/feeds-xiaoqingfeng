// Wizard deployment state-machine regression tests (isolated LuCI DOM/RPC).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { test } = require('node:test');
const source = fs.readFileSync(path.join(__dirname, '../htdocs/luci-static/resources/view/hometunnel/wizard.js'), 'utf8');

function fixture(initial = 'unbound') {
  const calls = [], polls = [], timers = [];
  let state = initial, verifyCode = 0, finishCode = 0, modeCode = 0, jobCode = 0, deployJob = { state: 'done', rc: 0 };
  const nodes = [];
  function E(tag, attrs, children) {
    if (typeof attrs !== 'object' || attrs === null || Array.isArray(attrs)) { children = attrs; attrs = {}; }
    const el = { tag, attrs, children: [], value: attrs.value || '', disabled: false, style: {}, textContent: '', innerHTML: '', listeners: {},
      appendChild(child) { this.children.push(child); if (child && typeof child === 'object') child.parentNode = this; return child; },
      addEventListener(ev, fn) { this.listeners[ev] = fn; },
      click() { assert(this.listeners.click, `missing click on ${this.textContent}`); this.listeners.click({ preventDefault() {} }); }
    };
    if (Array.isArray(children)) children.forEach(x => el.appendChild(x));
    else if (children !== undefined) el.textContent = String(children);
    nodes.push(el); return el;
  }
  const rpc = { exec: async (_cmd, args) => {
    calls.push(args);
    const op = args[0];
    if (op === 'deploy-state') return { code: 0, stdout: JSON.stringify({ state, host: 'ctl.example.org' }) };
    if (op === 'deploy-verify') { if (!verifyCode) state = 'verified'; return { code: verifyCode, stderr: verifyCode ? 'health pending' : '' }; }
    if (op === 'deploy-finish') { if (!finishCode) state = 'ready'; return { code: finishCode, stderr: finishCode ? 'route failed' : '' }; }
    if (op === 'job') return { code: jobCode, stderr: 'could not start job' };
    if (op === 'deploy-complete') { if (!modeCode) state = 'complete'; return { code: modeCode, stderr: modeCode ? 'apply failed' : '' }; }
    if (op === 'jobstatus') return { code: 0, stdout: deployJob.state === 'done' ? `done:${deployJob.rc}` : deployJob.state };
    if (op === 'deploy-check') return { code: 0, stdout: '{"state":"clean"}' };
    return { code: 0, stdout: '' };
  }, read_direct: async () => 'upload output', stat: async (name) => name.includes('cert.pem') || name.includes('oauth.json') ? { size: 1 } : Promise.reject(new Error('missing')) };
  const uci = { get: (_pkg, _sec, key) => ({ domain: 'example.org', tunnel_id: 'abc', ctl_hostname: 'ctl', mode: 'ondemand' })[key], sections: () => [] };
  const context = { E, fs: rpc, poll: { add(fn) { polls.push(fn); } }, uci, ui: {}, view: { extend: x => x }, htui: { apply: x => x },
    L: { bind: (fn, self, ...args) => fn.bind(self, ...args), url: () => '/status' },
    _: s => { const wrapped = new String(s); wrapped.format = (...args) => s.replace(/%s/g, () => args.shift()); return wrapped; },
    Promise, window: { setTimeout: fn => timers.push(fn) }, location: { reload() {}, href: '' } };
  const wizard = vm.runInNewContext(`(function () { ${source}\n})()`, context);
  const find = text => nodes.find(n => n.tag === 'button' && String(n.textContent) === text);
  const flush = async () => { for (let i = 0; i < 12; i++) await new Promise(resolve => setImmediate(resolve)); };
  return { wizard, calls, polls, timers, E, find, flush,
    setState: s => { state = s; }, setVerifyCode: n => { verifyCode = n; }, setFinishCode: n => { finishCode = n; }, setModeCode: n => { modeCode = n; }, setJobCode: n => { jobCode = n; },
    setDeployJob: s => { deployJob = s; }, getState: () => state, nodes };
}

test('pending after reload offers verify without upload or rebind', async () => {
  const f = fixture('pending');
  await f.wizard.probeState();
  assert.equal(f.wizard.getStep(), 5);
  f.wizard.step5(f.E('div'));
  await f.flush();
  assert(f.find('Retry Verification'));
  assert(!f.find('Deploy Now'));
  f.setVerifyCode(1);
  f.find('Retry Verification').click(); await f.flush();
  assert(f.calls.some(c => c[0] === 'deploy-verify'));
  assert(!f.calls.some(c => c[0] === 'oauth-deploy' || c[0] === 'deploy-check' || c[0] === 'set' || c[0] === 'deploy-finish'));
  assert.equal(f.wizard.getStep(), 5);
});

test('successful bind with health pending stays on deployment step', async () => {
  const f = fixture();
  await f.wizard.probeState();
  f.wizard.step5(f.E('div'));
  f.find('Deploy Now').click(); await f.flush();
  f.setState('pending'); f.setVerifyCode(1);
  await f.polls[0]().catch(() => {}); await f.flush();
  assert.equal(f.wizard.getStep(), 5);
  assert(f.find('Retry Verification'));
  assert.equal(f.find('Deploy Now').style.display, 'none');
  assert(!f.calls.some(c => c[0] === 'mark' || c[0] === 'route-and-regen'));
});

test('retry after health recovers verifies then finishes without redeploy', async () => {
  const f = fixture('pending'); await f.wizard.probeState(); f.wizard.step5(f.E('div')); await f.flush();
  f.find('Retry Verification').click(); await f.flush();
  assert.equal(f.wizard.getStep(), 6);
  assert(f.calls.some(c => c[0] === 'deploy-verify'));
  assert(f.calls.some(c => c[0] === 'deploy-finish'));
  assert(!f.calls.some(c => c[0] === 'job' || c[0] === 'set'));
});

test('verified recovery finishes routes before step six', async () => {
  const f = fixture('verified');
  await f.wizard.probeState();
  assert.equal(f.wizard.getStep(), 5);
  f.wizard.step5(f.E('div')); await f.flush();
  assert(f.calls.some(c => c[0] === 'deploy-finish'));
  assert.equal(f.wizard.getStep(), 6);
  assert(!f.calls.some(c => c[0] === 'oauth-deploy' || c[0] === 'deploy-verify'));
});

test('route failure remains retryable and never marks ready', async () => {
  const f = fixture('verified'); f.setFinishCode(1);
  await f.wizard.probeState(); f.wizard.step5(f.E('div')); await f.flush();
  assert.equal(f.wizard.getStep(), 5);
  assert(f.find('Retry Publishing'));
  assert(!f.calls.some(c => c[0] === 'mark'));
});

test('step six never records completion when mode application fails', async () => {
  const f = fixture('ready'); f.setModeCode(1);
  await f.wizard.probeState(); f.wizard.step6(f.E('div'));
  f.find('Verify').click(); await f.flush();
  assert(!f.calls.some(c => c[0] === 'mark' && c[1] === 'worker-verified'));
  assert.equal(f.find('Verify').disabled, false);
  assert.equal(f.timers.length, 0);
});

test('missing upload job shows error and re-enables deployment', async () => {
  const f = fixture(); await f.wizard.probeState(); f.wizard.step5(f.E('div'));
  f.setDeployJob({ state: 'missing' });
  const button = f.find('Deploy Now');
  await f.wizard.watchDeploy(f.E('pre'), button).catch(() => {});
  assert.equal(button.disabled, false);
});
test('failed upload job launch does not poll and allows retry', async () => {
  const f = fixture(); f.setJobCode(1);
  await f.wizard.probeState(); f.wizard.step5(f.E('div'));
  f.find('Deploy Now').click(); await f.flush();
  assert.equal(f.polls.length, 0);
  assert.equal(f.find('Deploy Now').disabled, false);
});

test('state readback failure cannot unlock step six', async () => {
  const f = fixture('error');
  await f.wizard.probeState();
  assert.equal(f.wizard.getStep(), 5);
  f.wizard.step5(f.E('div')); await f.flush();
  assert(!f.find('Deploy Now'));
});
