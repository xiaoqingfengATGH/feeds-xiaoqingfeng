"""Host-only listener/schema and INPUT planner contracts (Lua 5.1)."""
import pathlib, unittest
from lupa.lua51 import LuaRuntime
ROOT=pathlib.Path(__file__).resolve().parents[1]/'files/usr/share/homepublish'
class FirewallTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().root=str(ROOT).replace('\\','/')
  self.lua.execute('''
   C=dofile(root..'/canonical-v2.lua')
   function config()
    return {schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.1',port=8443}}},services={}}
   end
   function valid(c) local r,e=C.validate(c);assert(r,e);return r end
  ''')
 def test_auto_is_explicit_and_legacy_remains_unchanged(self):
  self.lua.execute('''
   local old=valid(config());assert(old.access_profile.listeners[1].bind_mode==nil)
   assert(old.access_profile.firewall==nil and old.access_profile.listeners[1].address=='192.168.1.1')
   local c=config();local l=c.access_profile.listeners[1]
   l.bind_mode='auto';l.network='';l.address='0.0.0.0'
   assert(valid(c).access_profile.listeners[1].bind_mode=='auto')
   l.family='ipv6';l.address='::';assert(valid(c).access_profile.listeners[1].address=='::')
   l.network='wan';assert(not C.validate(c));l.network='';l.address='fd00::1';assert(not C.validate(c))
   l.bind_mode='wildcard';assert(not C.validate(c))
  ''')
 def test_firewall_zones_are_explicit_strict_and_family_scoped(self):
  self.lua.execute('''
   local c=config();c.access_profile.firewall={ipv4_zones={'wan','lan'},ipv6_zones={}}
   local r=valid(c);assert(r.access_profile.firewall.ipv4_zones[1]=='wan')
   for _,f in ipairs({{ipv4_zones={},ipv6_zones={}}, {ipv4_zones={'wan','wan'},ipv6_zones={}},
     {ipv4_zones={'wan; accept'},ipv6_zones={}}, {ipv4_zones={'wan'},ipv6_zones={},chain='output'},
     {ipv4_zones={'wan'}}, {ipv4_zones={'wan'},ipv6_zones={'wan'}}}) do
    c.access_profile.firewall=f;local r,e,d=C.validate(c)
    assert(not r and d.field:find('access_profile.firewall',1,true),e)
   end
  ''')
 def test_inventory_lists_offline_zones_and_does_not_gate_binding_on_zone(self):
  self.lua.execute('''
   local N=dofile(root..'/network-inventory.lua')
   local inv=assert(N.normalize({interface={{interface='lan',up=true,device='br-lan',['ipv4-address']={{address='192.168.1.1'}}}}},
    {{name='wan',network={'pppoe'}},{name='lan',network={'lan'}},{name='guest',network={'lan'}},{name='empty'}}))
   assert(#inv.zones==4 and inv.zones[1]=='empty')
   local c=config();local b,e=N.resolve(c.access_profile.listeners[1],inv);assert(b,e and e.error)
   assert(b.zone==nil and #b.zones==2)
   local auto={family='ipv4',bind_mode='auto',network='',address='0.0.0.0'}
   assert(N.resolve(auto,nil).address=='0.0.0.0')
   auto.address='192.168.1.1';assert(not N.resolve(auto,inv))
   local ok,e=N.validate_firewall({ipv4_zones={'wan'},ipv6_zones={}},inv);assert(ok,e and e.error)
   local ok,e=N.validate_firewall({ipv4_zones={'missing'},ipv6_zones={}},inv)
   assert(not ok and e.error_code=='ZONE_UNAVAILABLE' and e.field=='access_profile.firewall.ipv4_zones')
  ''')
 def test_zone_inventory_summary_tracks_unattached_zone_changes(self):
  self.lua.execute('''
   local N=dofile(root..'/network-inventory.lua')
   local a=assert(N.normalize({interface={}},{{name='wan'}}))
   local b=assert(N.normalize({interface={}},{{name='lan'}}))
   assert(a.summary~=b.summary,'offline zone changes must invalidate inventory summary')
  ''')
 def test_planner_only_enabled_service_ports_deduplicated_dual_stack(self):
  self.lua.execute('''
   local P=dofile(root..'/product-firewall-plan.lua')
   local c=config();c.access_profile.listeners[2]={listener_id='v6',family='ipv6',bind_mode='auto',network='',address='::',port=8443}
   c.access_profile.firewall={ipv4_zones={'wan','lan'},ipv6_zones={'wan'}}
   function service(id,t,enabled)
    local s={service_id=id,name=id,type=t,enabled=enabled,backend={addressFamily='ipv4',host='192.168.1.2',port=80,allowed_ranges={'192.168.1.0/24'}},authentication_review={authentication='confirmed',management=false}}
    if t=='https_proxy' then s.hostname=id..'.example';s.upstream_scheme='http';s.certificate_mode='inherit'
    elseif t=='tls_passthrough' then s.hostname=id..'.example'
    elseif t=='tcp_forward' then s.listen_port=9000 end
    return s
   end
   c.services={service('web','https_proxy',true),service('tls','tls_passthrough',true),service('ssh','ssh',true),service('tcp','tcp_forward',true)}
   local inv={status='ok',zones={'wan','lan'}}
   local rules,e=P.plan(c,inv);assert(rules,e and e.error);assert(#rules==6)
   local seen={}
   for _,r in ipairs(rules) do
    local n=0;for k in pairs(r) do assert(k=='family' or k=='zone' or k=='port' or k=='protocol' or k=='dest_ip');n=n+1 end
    assert(n==(r.family=='ipv4' and 5 or 4) and r.protocol=='tcp' and (r.port==8443 or r.port==9000))
    assert(r.dest_ip==(r.family=='ipv4' and '192.168.1.1' or nil),'explicit bind must scope destination; auto must omit it')
    local key=r.family..r.zone..r.port;assert(not seen[key]);seen[key]=true
   end
   for i=1,4 do
    for j,s in ipairs(c.services) do s.enabled=i==j end
    local r=assert(P.plan(c,inv));assert(#r==3 and r[1].port==(i==4 and 9000 or 8443),'each service type must independently require its port')
   end
   for _,s in ipairs(c.services) do s.enabled=true end
   c.services[4].listen_port=9001
   local changed=assert(P.plan(c,inv));local added,removed=0,0
   local function key(r)return r.family..r.zone..r.port end
   local before,after={},{};for _,r in ipairs(rules) do before[key(r)]=true end
   for _,r in ipairs(changed) do after[key(r)]=true;if not before[key(r)] then added=added+1;assert(r.port==9001) end end
   for _,r in ipairs(rules) do if not after[key(r)] then removed=removed+1;assert(r.port==9000) end end
   assert(added==3 and removed==3,'port change must produce only affected tuples')
   c.services[4].listen_port=9000
   c.services[1].enabled=false;c.services[2].enabled=false;c.services[3].enabled=false
   assert(#assert(P.plan(c,inv))==3)
   c.services[4].enabled=false;assert(#assert(P.plan(c,inv))==0)
   c.access_profile.firewall=nil;assert(#assert(P.plan(c,nil))==0)
   c.services[1].enabled=true;c.access_profile.firewall={ipv4_zones={'missing'},ipv6_zones={'wan'}}
   local r,e=P.plan(c,inv);assert(not r and e.error_code=='ZONE_UNAVAILABLE')
   c.access_profile.firewall={ipv4_zones={'wan'},ipv6_zones={'wan'},chain='forward'}
   local r,e=P.plan(c,inv);assert(not r and e.error_code=='INVALID_CONFIG')
  ''')
if __name__=='__main__': unittest.main()
