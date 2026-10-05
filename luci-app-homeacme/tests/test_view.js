// SPDX-License-Identifier: GPL-3.0-or-later
const fs = require('fs');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
const calls = [];
function E(tag, attrs, children) {
 if (arguments.length === 2) { children = attrs; attrs = {}; }
 return { tag, attrs, children };
}
const poll = { add() {} };
const render = new Function('E', '_', 'cbi_update_table', 'poll', 'callCertificates', source.slice(source.indexOf('function _renderCerts(')) + '\nreturn _renderCerts;')(
 E, s => s, (table, rows) => calls.push(rows), poll, () => Promise.resolve({ certificates: [] }));
const row = { id: '/state/a/fullchain.cer', certificate: '/state/a/fullchain.cer', algorithm: 'RSA', bits: 2048, curve: '', sans: ['<img src=x onerror=alert(1)>'], issuer: '<b>issuer</b>', status: 'valid', not_before: 1, not_after: 2000000000, configurations: ['section'], exports: [], fullchain_present: true, private_key_present: false };
const tree = render({ certificates: [row, {...row, id:'/state/a_ecc/fullchain.cer', algorithm:'EC', bits:256}], truncated:false });
assert.equal(calls[0].length, 2);
assert(calls[0].every(r => r.every(cell => typeof cell === 'object' && cell.tag)), 'Every dynamic cell must be a DOM node, never HTML');
assert(JSON.stringify(tree).includes('Certificate instances'));
assert(JSON.stringify(calls).includes('<img src=x onerror=alert(1)>'));
assert(!source.slice(source.indexOf('function _renderCerts(')).includes('innerHTML'));
render({error:true});
console.log('PASS instance table / two algorithms / text-node cells / RPC error rendering');
