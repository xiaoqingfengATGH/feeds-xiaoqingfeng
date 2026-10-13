'use strict';
'require baseclass';
// Same input boundaries as the core Lua adapter; backend remains authoritative.
var rules = {
 configuration: function(c, hosts) {
  if (c.enabled === '0') return true;
  function integer(v, lo, hi) { return typeof v === 'string' && /^\d+$/.test(v) && +v >= lo && +v <= hi; }
  if (c.enabled !== '1' || c.exposure_approved !== '1') return 'Explicit exposure approval required';
  if (!integer(c.ttl, 1, 120) || !integer(c.port, 1024, 65535) || !integer(c.bind_port, 1024, 65535)) return 'Invalid integer or port range';
  if (+c.port === +c.bind_port) return 'The two isolated ports must differ';
  if (!rules.server(c.stun_server) || !rules.server(c.http_server)) return 'Invalid discovery server';
  if (hosts.length < 1 || hosts.length > 16) return 'Configure 1–16 services';
  var seen = {};
  for (var i = 0; i < hosts.length; i++) {
   if (!rules.hostname(hosts[i].name) || !rules.upstream(hosts[i].upstream) || seen[hosts[i].name]) return 'Invalid or duplicate service';
   seen[hosts[i].name] = true;
  }
  return true;
 },
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
