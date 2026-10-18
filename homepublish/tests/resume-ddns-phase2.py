from pathlib import Path
p=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng/homepublish/tests/deploy-ddns-phase2.py')
code=p.read_text();ns={};exec(code[:code.index('def main():')],ns)
import json
ns['report']=json.loads((ns['E']/'deployment.json').read_text());ns['B']=ns['report']['backup'];ns['s']=ns['report']['before']['status'];ns['before']=ns['report']['before'];ns['old']=ns['before']['controller']['homepublish']['instances']['controller']['pid'];ns['files']=ns['report']['hashes']
# New canonical read adds explicit manual DNS, without changing saved revision or user policy.
for k in ['saved_config','active_config']:
 for service in ns['s'][k]['services']:service.setdefault('dns',{'mode':'manual'})
ns['report']['comparison_note']='Legacy omitted DNS canonicalizes to explicit manual on read; no save RPC performed.'
segment=code[code.index(" report['start_result']"):code.index('try:main()')]
exec('\n'.join(x[1:] if x.startswith(' ') else x for x in segment.splitlines()),ns)
