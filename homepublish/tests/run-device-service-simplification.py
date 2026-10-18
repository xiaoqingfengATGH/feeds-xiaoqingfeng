"""Reuse real isolated traffic acceptance with ordinary no-declaration service payloads."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('traffic',Path(__file__).with_name('run-device-upstream-tls-traffic.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.EVIDENCE=m.REPO/'docs/evidence/ui-simplification/service-simplification-traffic.json'
original=m.request
def request(q):
 if q.get('action')=='save':
  for s in q['config']['services']:
   s['backend'].pop('allowed_ranges',None)
   s.pop('authentication_review',None)
 result=original(q)
 if q.get('action')=='save' and 'saved_config' in result:
  for s in result['saved_config']['services']:
   assert 'allowed_ranges' not in s['backend'] and 'authentication_review' not in s
 return result
m.request=request
if __name__=='__main__':raise SystemExit(m.main())
