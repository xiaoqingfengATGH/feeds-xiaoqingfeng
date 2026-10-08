import os, pathlib, re, subprocess, tempfile

root = pathlib.Path(__file__).resolve().parents[2]
src = (root/'hometunnel/files/usr/share/hometunnel/hometunnel.sh').read_text()
js = (root/'luci-app-hometunnel/htdocs/luci-static/resources/view/hometunnel/wizard.js').read_text()
assert "['deploy-check', candidate]" in js, 'wizard must check the typed hostname, not the stored one'
match = re.search(r'(?ms)^cmd_deploy_check\(\) \{.*?^\}\n', src)
assert match, 'deploy-check function missing'
with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as td:
    oauth = pathlib.Path(td)/'oauth.json'
    oauth.write_text('{"account_id":"test-account"}')
    script = '''#!/bin/sh
OAUTH_JSON="%s"
get_() { case "$1" in domain) echo innonext.win;; ctl_hostname) echo stored;; esac; }
oauth_valid_token() { echo test-token; }
cf_zone_id() { echo test-zone; }
ctl_domain_check() { case "$3" in candidate.innonext.win) echo clean;; stored.innonext.win) echo worker:other;; fails.innonext.win) echo 'error:worker-domain lookup failed';; *) echo dns:A;; esac; }
msg() { printf '%%s\\n' "$1"; }
%s
cmd_deploy_check candidate
cmd_deploy_check stored
cmd_deploy_check fails
cmd_deploy_check invalid_host
''' % (oauth, match.group(0))
    run = subprocess.run(['sh'], input=script, text=True, capture_output=True)
    assert run.returncode == 0, run.stderr
    assert run.stdout.splitlines() == [
        '{"state":"clean"}',
        '{"state":"conflict","kind":"worker","by":"other"}',
        '{"state":"error","error":"domain lookup failed"}',
        '{"state":"error","error":"invalid switch subdomain"}',
    ], run.stdout
print('candidate hostname preflight: PASS')
