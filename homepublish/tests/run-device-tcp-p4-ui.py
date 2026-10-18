#!/usr/bin/env python3
"""Run existing owned device fixture with real LuCI-click RPC exercise."""
import ast,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=ROOT/'homepublish/tests/run-device-tcp-p4-policy.py'
tree=ast.parse(p.read_text())
replacement=ast.parse('''def exercise():
 c['publication_policy']={'mode':'continuous','boot_restore':False}
 worker={'name':'homepublish-p4-policy','instances':{'controller':{'command':['/usr/bin/lua',REMOTE+'/device-tcp-p4-policy-rpc.lua','serve'],'stdout':True,'stderr':True}}}
 ssh('ubus call service set '+repr(json.dumps(worker)));ssh('sleep 2')
 saved=request({'action':'save','expected_revision':0,'config':c});assert saved['saved_revision']==1,saved
 result=subprocess.run(['node',str(ROOT/'luci-app-homepublish/tests/p4-lifecycle-browser.cjs')],cwd=ROOT,timeout=180)
 assert result.returncode==0,('browser lifecycle failed',result.returncode)
''').body[0]
tree.body=[replacement if isinstance(n,ast.FunctionDef) and n.name=='exercise' else n for n in tree.body]
# Keep the independent policy evidence untouched; all fixture setup/cleanup remains identical.
for n in ast.walk(tree):
 if isinstance(n,ast.Constant) and isinstance(n.value,str) and n.value.startswith('task25-'):n.value=n.value.replace('task25-','ui-lifecycle-')
 if isinstance(n,ast.Constant) and n.value=='P4_TASK25_BACKGROUND_POLICY_GREEN':n.value='P4_UI_LIFECYCLE_FIXTURE_CLEAN_GREEN'
ast.fix_missing_locations(tree)
exec(compile(tree,str(p),'exec'),{'__file__':str(p),'__name__':'__main__'})
