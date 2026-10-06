#!/usr/bin/env python3
"""Actual init network helpers must propagate boundary failures."""
import pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hv-network-') as d:
 p=pathlib.Path(d)
 (p/'controller').write_text((root/'usr/share/homevpn/service-control.sh').read_text().replace('/usr/share/homevpn/service-lock.sh',str(root/'usr/share/homevpn/service-lock.sh')))
 (p/'init').write_text((root/'etc/init.d/homevpn').read_text().replace('/usr/share/homevpn/service-control.sh',str(p/'controller')).replace('/etc/init.d/firewall',str(p/'firewall')))
 (p/'firewall').write_text('#!/bin/sh\nexit 1\n');(p/'firewall').chmod(0o755)
 driver=f'''extra_command() {{ :; }}
 . {p}/init
 logger_tag() {{ :; }}
 INCLUDE_FILE={p}/include
 uci() {{
  [ "$1" != -q ] || shift
  case "$1" in get) return 1;; commit) [ "$FAIL" != commit ];; *) return 0;; esac
 }}
 nft() {{
  case "$*" in
  *'list chain'*) echo 'ip saddr 192.0.2.0/24 accept comment "homevpn" # handle 1';;
  *'list tables'*) echo "table inet $NFT_TBL";;
  *'list table'*) return 0;;
  *'delete rule'*|*'delete table'*) [ "$FAIL" != nft ];;
  esac
 }}
 FAIL="$1"
 case "$FAIL" in
 reload) ensure_firewall;;
 commit|nft) drop_client_include;;
 esac
 '''
 (p/'driver').write_text(driver)
 for fault in ['reload','commit','nft']:
  (p/'include').touch()
  r=subprocess.run(['busybox','ash',str(p/'driver'),fault],capture_output=True,text=True)
  assert r.returncode!=0,(fault,'network failure was swallowed',r.stdout,r.stderr)
  if fault!='reload':assert not (p/'include').exists(),'cleanup must continue after boundary failure'
 print('PASS real firewall helpers surface reload/commit/nft-delete faults and continue cleanup')
