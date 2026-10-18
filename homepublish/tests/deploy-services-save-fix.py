"""Deploy only canonical loader fix using established protected source deployment."""
from pathlib import Path
source=Path(__file__).with_name('deploy-upstream-tls-source.py')
code=source.read_text()
code=code.replace("['canonical-v2.lua','direct-renderer.lua']", "['canonical-v2.lua']")
code=code.replace("['product.js','services.js']", "[]")
code=code.replace('upstream-tls-deploy-', 'services-save-deploy-')
code=code.replace('input-firewall/upstream-tls-deploy.json', 'input-firewall/services-save-deploy.json')
code=code.replace("target+'.upstream-tls-new'", "target+'.services-save-new'")
exec(compile(code,str(source),'exec'),{'__name__':'__main__','__file__':str(source)})
