'use strict';
'require baseclass';
// Same input boundaries as the core Lua adapter; backend remains authoritative.
var rules = {
 hostname: function(v) {
  return typeof v === 'string' && v.length <= 253 && v.indexOf('.') > 0 &&
   v.split('.').every(function(l) { return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(l); });
 },
 upstream: function(v) {
  var m = typeof v === 'string' && v.match(/^http:\/\/(\d+\.\d+\.\d+\.\d+):(\d+)$/);
  if (!m) return false;
  var a = m[1].split('.').map(Number), p = Number(m[2]);
  if (a.some(function(n,i) { return n > 255 || String(n) !== m[1].split('.')[i]; })) return false;
  return p >= 1024 && p <= 65535 && (a[0] === 127 || a[0] === 10 ||
   (a[0] === 192 && a[1] === 168) || (a[0] === 172 && a[1] >= 16 && a[1] <= 31));
 },
 server: function(v) {
  if (typeof v !== 'string' || !v || v.length > 253) return false;
  var m = v.match(/^([^:]+)(?::(\d+))?$/);
  return !!m && (!m[2] || (+m[2] >= 1 && +m[2] <= 65535)) &&
   m[1].split('.').every(function(l) { return /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(l); });
 }
};
return baseclass.extend(rules);
