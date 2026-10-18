"""Narrow wildcard source deploy, established controller/config-preserving sequence."""
from pathlib import Path
source=Path(__file__).with_name('deploy-upstream-tls-source.py')
code=source.read_text()
code=code.replace("['canonical-v2.lua','direct-renderer.lua']", "['certificate-reference.lua','canonical-v2.lua','direct-renderer.lua']")
code=code.replace("['product.js','services.js']", "[]")
code=code.replace('upstream-tls-deploy-', 'wildcard-deploy-')
code=code.replace('input-firewall/upstream-tls-deploy.json', 'input-firewall/wildcard-deploy.json')
code=code.replace("for x in files)+' etc/homepublish", "for x in files if not x.endswith('/certificate-reference.lua'))+' etc/homepublish")
code=code.replace("target+'.upstream-tls-new'", "target+'.wildcard-new'")
exec(compile(code,str(source),'exec'),{'__name__':'__main__','__file__':str(source)})
