#!/usr/bin/env python3
"""Build a complete source inventory; never import device scripts."""
import ast
import csv
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
runner = ast.parse((HERE/'run-current-suite.py').read_text())
manifest = next(n.value for n in ast.walk(runner) if isinstance(n, ast.Constant) and isinstance(n.value, str) and 'test-init-restart-semantics.py' in n.value).split()
current = set(manifest) | {'test-canonical.lua','test-direct.lua','test-certificate-model.lua','test-certificate-san.lua','test-config.lua','test-core.lua','test-publication-config.lua','test-certificate-inventory.lua','test-certificate-metadata.py','run-device-retained-contracts.py'} | {'run-current-suite.py','run-device-restart.py','device-restart.lua','run-device-lua-store.py','device-lua-store.lua','worker.test.mjs','publication-worker.test.mjs','publication-fixture.mjs','publication-bridge.mjs','check-current-ipk.py','check-companion-ipk.py','test-retired-entrypoints.py','build-test-inventory.py'}
tracked = subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','homepublish/tests'], cwd=ROOT, text=True).splitlines()
paths = sorted({ROOT/p for p in tracked if (ROOT/p).is_file() and '__pycache__' not in p and '/.pytest_cache/' not in p and not p.endswith('.csv')})
rows=[]
for path in paths:
    text = path.read_text(encoding='utf-8-sig', errors='replace') if path.suffix != '.bin' else ''
    if path.name.startswith(('deploy-', 'finalize-', 'resume-')) or path.name in ('router-r7-browser-setup.sh',):
        decision, reason = 'retained-disabled', 'Historical production writer or setup; unconditional early exit. Preserve source for unique assertions and dependency migration, not execution.'
    elif path.name in current:
        decision, reason = 'current', 'Explicit runnable suite, dependency fixture, inventory or actual-package check.'
    elif path.suffix in ('.md',) or path.name == 'Makefile':
        decision, reason = 'documentation', 'Current guide or historical audit/entrypoint documentation.'
    else:
        decision, reason = 'retained-specialized', 'Unique specialized or historical coverage not proven equivalent to current suite; not an acceptance pass. Requires individual environment and isolation review before execution.'
    deps=[]
    if path.suffix == '.py':
        tree=ast.parse(text)
        deps=sorted({n.module or '' for n in ast.walk(tree) if isinstance(n,ast.ImportFrom)} | {a.name for n in ast.walk(tree) if isinstance(n,ast.Import) for a in n.names})
    markers=[m for m in ('/home/eric','homepublish_store','ssh','subprocess','nixio','procd','nft','openssl','nginx') if m in text]
    rows.append({'path':path.relative_to(ROOT).as_posix(),'decision':decision,'reason':reason,'imports':';'.join(deps),'dependency_markers':';'.join(markers)})
output=HERE/'TEST-INVENTORY.csv'
with output.open('w',newline='',encoding='utf-8-sig') as stream:
    writer=csv.DictWriter(stream,fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)
assert len(rows)==len({r['path'] for r in rows})
from collections import Counter
print('INVENTORY_COMPLETE',len(rows),dict(Counter(r['decision'] for r in rows)))
