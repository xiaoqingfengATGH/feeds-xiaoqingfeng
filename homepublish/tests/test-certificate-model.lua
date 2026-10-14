-- Unified ingress default is normalized into the existing durable service references.
local T=dofile(arg[1]..'/homepublish/tests/test-canonical.lua')
local c=T.fixture();c.default_certificate_ref='acme:shared';c.services[1].certificate_ref=nil;c.services[1].hostname='NAS.Example.Test'
local n,e=T.model.validate(c);assert(n,e)
assert(n.default_certificate_ref=='acme:shared' and n.services[1].certificate_ref=='acme:shared')
assert(n.services[1].hostname=='nas.example.test')
c.services[2]={service_id='photos',name='Photos',hostname='photos.example.test',backend=c.services[1].backend,certificate_ref='acme:independent',authentication_review=c.services[1].authentication_review}
n=assert(T.model.validate(c));assert(n.services[2].certificate_ref=='acme:independent')
c.services[2].hostname='NAS.example.test';assert(not T.model.validate(c),'case-normalized duplicate must fail')
c.default_certificate_ref='/etc/key';assert(not T.model.validate(c),'default cannot be a path')
print('PASS shared default inheritance, independent override, case-normalized uniqueness and legacy references')
