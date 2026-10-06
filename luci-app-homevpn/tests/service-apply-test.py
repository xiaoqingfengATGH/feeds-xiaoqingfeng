#!/usr/bin/env python3
"""Real apply/start/boot chain in BusyBox; only OS boundaries are isolated."""
import pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hv-apply-') as d:
 p = pathlib.Path(d)
 for folder in ['etc/config','etc/swanctl/conf.d','etc/strongswan.d/charon','var/etc','tmp/dnsmasq.d','bin']:
  (p/folder).mkdir(parents=True)
 (p/'blocked').mkdir()
 (p/'etc/config/homevpn').write_text('fixture')
 controller=(root/'usr/share/homevpn/service-control.sh').read_text().replace('/usr/share/homevpn/service-lock.sh',str(root/'usr/share/homevpn/service-lock.sh'))
 controller=controller.replace('/etc/init.d/',str(p)+'/etc/init.d/')
 (p/'controller').write_text(controller)
 source=(root/'etc/init.d/homevpn').read_text().replace('/usr/share/homevpn/service-control.sh',str(p/'controller'))
 import re
 source=re.sub(r'/(?:etc|var|tmp)/',lambda m: str(p)+m.group(),source)
 # The controller path was already isolated before absolute-path rewriting.
 source=source.replace(str(p) + str(p) + '/controller', str(p) + '/controller')
 (p/'init').write_text(source)
 for name in ['firewall','swanctl','dnsmasq']:
  f=p/'etc/init.d'/name;f.parent.mkdir(exist_ok=True)
  f.write_text('#!/bin/sh\n[ "$FAULT" != '+name+' ]\n');f.chmod(0o755)
 (p/'bin/nft').write_text('#!/bin/sh\n[ "$FAULT" != nft ] || exit 1\ncase "$*" in\n \'-f -\') [ "$FAULT" != nft-insert ];;\n \'list tables\') case "$FAULT" in nft-delete-table) echo \'table inet homevpn\';; esac;;\n \'-a list chain inet fw4 forward\') [ "$FAULT" != nft-delete-rule ] || echo \'accept comment "homevpn client-src" # handle 1\';;\n \'delete rule \'*) [ "$FAULT" != nft-delete-rule ];;\n \'delete table \'*) [ "$FAULT" != nft-delete-table ];;\n \'add table \'*) [ "$FAULT" != nft-add-table ];;\n \'add chain \'*) [ "$FAULT" != nft-add-chain ];;\n \'add rule \'*) [ "$FAULT" != nft-add-rule ];;\nesac\n');(p/'bin/nft').chmod(0o755)
 driver='''extra_command() { :; }
. "$SANDBOX/init"
logger_tag() { :; }
hv_get() { case "$1" in enabled) echo 1;; ip_mode) echo subnet;; pool_subnet) echo 10.99.0.0/24;; cert_mode) if [ "$FAULT" = certificate ]; then echo selfsigned; else echo import; fi;; masq) case "$FAULT" in nft-add-*|masq-ok) echo 1;; esac;; remote) echo vpn.example;; esac; }
uci() {
 [ "$1" != -q ] || shift
 case "$1" in
 get) case "$2" in network.lan.ipaddr) echo 192.0.2.1;; network.lan.device) echo br-lan;; *) return 1;; esac;;
 *) [ "$FAULT" != uci ];;
 esac
}
ip() {
 case "$*" in
 'route') echo '192.0.2.0/24 dev br-lan src 192.0.2.1';;
 'route get '*) echo 'default via 192.0.2.254 dev br-lan';;
 'route show dev lo') [ "$FAULT" != route-read ] || return 1; [ "$FAULT" != route-delete ] || echo '10.98.0.0/24 dev lo';;
 'route del '*) [ "$FAULT" != route-delete ];;
 'route replace '*) [ "$FAULT" != route ];;
 esac
}
swanctl() { [ "$FAULT" != swanctl ]; }
hv_exclusive() { return 0; }
hv_with_lock() { "$@"; }
# Use import fixtures to avoid cryptographic generation in network tests.
printf cert > "$X509_DIR/homevpn-server.crt"
if [ "$FAULT" = certificate ]; then
 mkdir -p "$KEY_DIR" "$CA_DIR"
 printf key > "$KEY_DIR/homevpn-ca.key"
 printf key > "$KEY_DIR/homevpn-server.key"
 rm -f "$CA_DIR/homevpn-ca.crt" "$X509_DIR/homevpn-server.crt"
 openssl() { return 1; }
fi
[ "$FAULT" != secrets ] || SECRETS_FILE="$SANDBOX/blocked"
[ "$FAULT" != conf ] || CONN_FILE="$SANDBOX/blocked"
[ "$FAULT" != plugin ] || PLUGIN_FILE="$SANDBOX/blocked"
[ "$FAULT" != include ] || INCLUDE_FILE="$SANDBOX/blocked"
[ "$FAULT" != route-delete ] || hv_state 'mode=subnet' 'pool=10.98.0.0/24'
[ "$FAULT" != dnsmasq ] || printf old > "$DHCPHOST_FILE"
load_env
case "$ENTRY" in
 noop)
  MODE=dhcp
  render_conf && render_user_bindings && apply_include && apply_subnet_routes || exit 1
  uci() { return 0; }
  fw_rule_set existing || exit 1
  ensure_firewall || exit 1
  hv_state result=ok;;
 apply) apply_config regen;;
 rollback)
  hv_get() { case "$1" in enabled) echo 0;; ip_mode) echo subnet;; pool_subnet) echo 10.99.0.0/24;; cert_mode) if [ "$FAULT" = certificate ]; then echo selfsigned; else echo import; fi;; esac; }
  hv_install_guard() { :; }
  hv_stop_engine() { echo stopped >> "$SANDBOX/rollback"; }
  hv_cleanup_network() { echo cleaned >> "$SANDBOX/rollback"; }
  hv_set_enabled 1;;
 *) "$ENTRY";;
esac
rc=$?
printf 'RC=%s RESULT=%s\\n' "$rc" "$(state_get result)"
exit "$rc"
'''
 # Real hv_set_enabled changes enabled through UCI; keep its subsequent guard enabled.
 driver=driver.replace('echo 0;; ip_mode','echo 1;; ip_mode').replace('hv_install_guard() { :; }','hv_install_guard() { :; }\n  hv_ready() { return 1; }')
 (p/'etc/init.d/homevpn').write_text('#!/bin/sh\nexit 0\n');(p/'etc/init.d/homevpn').chmod(0o755)
 (p/'etc/swanctl/x509').mkdir()
 (p/'driver').write_text(driver)
 import os
 failures=[]
 for entry in ['apply','hv_start','boot','provision','reload_service','hv_regen','rollback','noop']:
  faults=['secrets','conf','plugin','include','route','route-read','route-delete','nft','nft-insert','nft-delete-rule','nft-delete-table','uci','firewall','swanctl','dnsmasq']
  if entry=='apply': faults+=['none','masq-ok','nft-add-table','nft-add-chain','nft-add-rule']
  elif entry!='rollback': faults+=['certificate']
  if entry=='noop': faults=['none']
  for fault in faults:
   p.chmod(0o700)
   state=p/'tmp/homevpn.state'
   state.unlink(missing_ok=True)
   env=dict(os.environ,SANDBOX=str(p),FAULT=fault,ENTRY=entry,PATH=str(p/'bin')+':'+os.environ['PATH'])
   r=subprocess.run(['busybox','ash',str(p/'driver')],env=env,capture_output=True,text=True)
   ok=(r.returncode==0 and 'RESULT=ok' in r.stdout) if fault in ['none','masq-ok'] else (r.returncode!=0 and 'RESULT=ok' not in r.stdout)
   if not ok: failures.append((entry,fault,r.returncode,r.stdout,r.stderr))
   if entry=='rollback' and fault!='none':
    trace=p/'rollback'
    if not trace.exists() or trace.read_text().splitlines()!=['stopped','cleaned']: failures.append(('rollback missing',fault,r.stderr))
    trace.unlink(missing_ok=True)
 assert not failures, failures
 print('PASS real apply/start/boot/provision/reload/regen + enable rollback: write, route, nft, UCI, firewall, daemon faults; happy path')
