-- SPDX-License-Identifier: Apache-2.0
-- DNS SAN only. Unicode must be converted to IDNA A-labels by the caller.
local M={}
local function dns(s)
 if type(s)~='string' then return nil end
 s=s:lower();if #s==0 or #s>253 or s:find('[^a-z0-9.%-]') or s:find('..',1,true) or s:sub(-1)=='.' then return nil end
 for label in s:gmatch('[^.]+') do if #label>63 or not label:match('^[a-z0-9]') or not label:match('[a-z0-9]$') then return nil end end
 if s:sub(1,1)=='.' then return nil end
 return s
end
function M.match(sans,host)
 host=dns(host);if not host or type(sans)~='table' then return nil end
 local wildcard=false
 for _,san in ipairs(sans) do
  if dns(san)==host then return 'exact' end
  if type(san)=='string' and san:sub(1,2)=='*.' then
   local suffix=dns(san:sub(3));local label,rest=host:match('^([^.]+)%.(.+)$')
   if suffix and label and rest==suffix then wildcard=true end
  end
 end
 return wildcard and 'wildcard' or nil
end
local function path(s)return type(s)=='string' and s:match('^/[a-zA-Z0-9_./%-]+$') and not s:find('..',1,true) end
local function command(s)
 local f=io.popen(s..' 2>/dev/null');if not f then return nil end
 local out=f:read(65537);f:close();if not out or #out>65536 then return nil end;return out
end
function M.read(file)
 -- Internal trusted resolver path only; NEVER expose file as an RPC parameter.
 if not path(file) then return nil,'trusted certificate path required' end
 local text=command('openssl x509 -in '..file..' -noout -dates -ext subjectAltName')
 if not text or not text:find('notAfter=',1,true) then return nil,'certificate parse failed' end
 local sans={};for san in text:gmatch('DNS:([^,%s]+)') do sans[#sans+1]=san:lower() end
 local valid=command('openssl x509 -in '..file..' -noout -checkend 0')
 return {sans=sans,not_before=text:match('notBefore=([^\n]+)'),not_after=text:match('notAfter=([^\n]+)'),status=valid and valid:find('Certificate will not expire',1,true) and 'valid' or 'expired'}
end
return M
