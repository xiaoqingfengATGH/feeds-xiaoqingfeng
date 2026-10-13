-- SPDX-License-Identifier: Apache-2.0
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local adapter=dofile(source..'/config.lua')
local core=dofile(source..'/core.lua')
local confdir=arg[2];if confdir=='' then confdir=nil end
local cursor=require('uci').cursor(confdir)
local c,err=adapter.load(cursor)
if arg[1]=='status' then
 local state=c and c.state or 'invalid'
 local publication=c and c.publication or 'invalid'
 print('{"state":"'..state..'","publication":"'..publication..'","mapped":"unknown","reachable":"unverified"}')
 os.exit(0)
end
if not c then io.stderr:write('HomeSTUN: '..err..'\n');os.exit(1) end
if arg[1]=='plan' then
 if c.state=='disabled' then print('disabled');os.exit(0) end
 local plan={'configured',c.ttl,c.bind_port,c.nginx.port,c.stun,c.http}
 if c.publication=='configured' then plan[#plan+1]='publish';plan[#plan+1]=c.router_token_file end
 print(table.concat(plan,'\n'))
elseif arg[1]=='render' and c.state=='configured' then
 local r=arg[3]
 if not r or not r:match('^/tmp/homestun%-service%-[%w]+$') then os.exit(1) end
 c.nginx.runtime=r;c.nginx.cert=r..'/cert.pem';c.nginx.key=r..'/key.pem'
 local out,e=core.render(c.nginx);if not out then io.stderr:write(e..'\n');os.exit(1) end
 io.write(out)
else os.exit(1) end
