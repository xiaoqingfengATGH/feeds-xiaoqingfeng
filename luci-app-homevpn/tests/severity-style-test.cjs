const fs = require('fs');
const vm = require('vm');
const assert = require('assert/strict');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '../htdocs/luci-static/resources/view/homevpn/overview.js'), 'utf8');
const palette = src.slice(src.indexOf('var CLR ='), src.indexOf('function replayFlash()'));
const validation = src.slice(src.indexOf('function validateCidr(pc)'), src.indexOf('\n\t\tvar sMasq'));
const declaration = src.match(/var cidrError = E\('div', .*\);/)[0];
const ctx = { _: s => s, sIpMode: {value:'subnet'}, sPc: {setAttribute(k,v){this[k]=v},focus(){this.focused=true}}, E(tag,attrs){return {attrs,style:{display:'none'},scrollIntoView(){this.scrolled=true}}} };
vm.createContext(ctx);
vm.runInContext(palette + '\n' + declaration + '\n' + validation, ctx);
assert(ctx.cidrError.attrs.style.includes(ctx.CLR.error.box));
for (const [value, accepted] of [['',false],['999.0.0.0/24',false],['10.100.1.0/7',false],['10.100.1.0/31',false],['10.100.1.0/24',true],['10.0.0.0/8',true],['10.0.0.0/30',true]]) {
 assert.equal(ctx.validateCidr(value),accepted,value);
 assert.equal(ctx.cidrError.style.display,accepted?'none':'');
 assert.equal(ctx.sPc['aria-invalid'],accepted?'false':'true');
 if(!accepted) { assert(ctx.sPc.focused); assert(ctx.cidrError.scrolled); }
}
ctx.sIpMode.value='dhcp'; assert(ctx.validateCidr(''));
ctx.sIpMode.value='lansubnet'; assert(ctx.validateCidr(''));
const withoutPalette=src.replace(palette,'');
assert(!/(?:color|background):\s*(?:#[0-9a-f]+|rgba?\()/i.test(withoutPalette));
assert.equal((src.match(/'style': 'font-size:90%;color:inherit'/g)||[]).length,2);
console.log('PASS: shared CIDR error palette; 9 CIDR/mode cases; visibility/ARIA/focus/scroll; no hardcoded colors outside palette; 2 theme-aware descriptions');

assert(src.includes("'id': 'homevpn-ip-actions', 'class': 'cbi-value-field', 'style': 'width:100%;max-width:100%'"));
assert(!src.includes("'class': 'cbi-section-descr', 'style': 'font-size:90%'"));
console.log('PASS: full-width IP action row; inline descriptions without callout styling');
