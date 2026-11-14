-- Current acme.sh directory identity, not retired UCI section identities.
package.path=arg[1]..'/homepublish/files/usr/share/homepublish/?.lua;'..package.path
local I=require('device-integrations');local C=require('certificate-metadata')
local actual,why=I.acme_source('*.example.test','rsa');assert(actual,why)
assert(actual.domain=='*.example.test' and actual.key_type=='rsa')
assert(actual.certificate==os.getenv('HP_ACME_STATE_DIR')..'/*.example.test/fullchain.cer')
assert(not I.acme_source('*.example.test','ecc'),'RSA fixture must not satisfy ECC lookup')
assert(not I.acme_source('../escape','rsa'),'unsafe domain accepted')
local source,e=I.certificate_source('acme:*.example.test','photos.example.test');assert(source,e)
assert(source.domain=='*.example.test' and source.key_type=='rsa')
assert(not I.certificate_source('acme:*.example.test','a.b.example.test'))
assert(not I.certificate_source('acme:*.example.test','unrelated.test'))
local rows=I.certificate_inventory().certificates
assert(#rows==1 and rows[1].certificate_ref=='acme:*.example.test')
assert(rows[1].domain=='*.example.test' and rows[1].key_type=='rsa' and #rows[1].sans==3)
local json=require('product-json').encode(rows)
assert(not json:find(os.getenv('HP_ACME_STATE_DIR'),1,true) and not json:find('key.pem',1,true))
assert(require('product-json').encode({certificates={}}):find('"certificates":%[%]'))
print('PASS actual directory identity, wildcard SAN, key algorithm and metadata path privacy')
