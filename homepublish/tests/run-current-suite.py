#!/usr/bin/env python3
"""Curated HomePublish tests: explicit selection, no implicit pytest discovery.

Host: run under Python with pytest and lupa installed. Target: --target runs
private-root tests on the authorized router; these do not deploy the package.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
HOST_TESTS = '''test-init-restart-semantics.py test-input-firewall-runtime.py
test-simple-device.py test_p1_lua_runner_safety.py test_legacy_lua_runner_safety.py
test-product-firewall.py test-startup-components.py test_p5_packaging.py
test-package.py test-backend-scope-defaults.py test-auto-listener-rendering.py
test-http-runtime.py test-http-ingress.py test-host-port-nat.py
test-product-probe.py test-upstream-tls.py test-owned-listeners.py test-retired-entrypoints.py test-current-lua-contracts.py'''.split()

def run(args):
    print('\n>>>', ' '.join(map(str, args)), flush=True)
    subprocess.run(args, cwd=HERE.parents[1], check=True)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ipk-dir', type=Path, help='also check exactly one core, LuCI and engine IPK from this directory')
    p.add_argument('--target', action='store_true', help='also execute isolated target tests')
    p.add_argument('--host', default='192.168.1.2')
    p.add_argument('--key', default='D:/DevPortal/CloudHosts/HomePri.key')
    args = p.parse_args()
    run([sys.executable, '-m', 'pytest', '-p', 'no:cacheprovider', '-q', *map(str, (HERE / f for f in HOST_TESTS))])
    run(['node', '--test', str(HERE/'worker.test.mjs'), str(HERE/'publication-worker.test.mjs')])
    if args.target:
        # restart runner currently hard-codes this endpoint; fail closed on mismatch.
        if args.host != '192.168.1.2' or args.key.replace('\\', '/') != 'D:/DevPortal/CloudHosts/HomePri.key':
            p.error('restart runner only supports 192.168.1.2 and its configured key')
        run([sys.executable, str(HERE/'run-device-retained-contracts.py')])
        for case in ('controller', 'marker', 'procd'):
            run([sys.executable, str(HERE/'run-device-restart.py'), 'current-suite-'+case, case])
        evidence = Path(os.environ.get('BH_AGENT_WORKSPACE') or (Path(os.environ['LOCALAPPDATA'])/'hermes/cache/scratch' if os.environ.get('LOCALAPPDATA') else Path.home()/'homepublish-test-evidence'))/'homepublish-current-suite'
        for case in ('contract','classification','faults','cleanup','resources','migration','safety','validation'):
            run([sys.executable, str(HERE/'run-device-lua-store.py'), '--host', args.host, '--key', args.key, '--case', case, '--label', 'suite-'+case, '--evidence', str(evidence)])
    if args.ipk_dir:
        packages = []
        for name in ('homepublish', 'luci-app-homepublish', 'homepublish-engines'):
            matches = list(args.ipk_dir.resolve().glob(name+'_*.ipk'))
            if len(matches) != 1:
                p.error(f'{name}: require exactly one IPK, found {len(matches)}')
            packages.append(matches[0])
        run([sys.executable, str(HERE/'check-current-ipk.py'), str(packages[0])])
        run([sys.executable, str(HERE/'check-companion-ipk.py'), '--complete', *map(str, packages[1:])])
    run([sys.executable, str(HERE/'build-test-inventory.py')])
    print('\nCURRENT_SUITE_PASS', flush=True)

if __name__ == '__main__':
    main()
