const fs = require('fs');
const assert = require('assert');
const src = fs.readFileSync(process.argv[2], 'utf8');
new Function(src); // LuCI module returns at top-level.
assert(src.includes("'acme_key_type'"), 'RPC must carry key type');
assert(src.includes("method: 'discover_acme'"));
assert(src.includes("'homevpn-acme-type'"));
const calls = src.match(/callSetSettings\.apply\([^\n]+/g) || [];
assert(calls.length === 1 && calls[0].includes('payload'), 'one shared immutable RPC submission');
assert(src.includes("domain, acme.selected || set.acme_key_type || 'rsa'"), 'immutable payload must preserve discovered ACME selection');
assert.equal((src.match(/return saveSettings\(/g) || []).length, 2, 'both entrances use the gate');
assert(!src.includes('st.acme_ready &&'), 'hint must use fresh discovery, not saved status');
console.log('PASS: LuCI syntax, discovery RPC and shared save gate');
