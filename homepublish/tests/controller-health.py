#!/usr/bin/env python3
"""Test-only fixed loopback TLS/backend probe; never production SAN authority."""
import pathlib, socket, ssl, sys, time
root=pathlib.Path(sys.argv[1]);port=int(sys.argv[2])
host=sys.argv[3] if len(sys.argv)>3 else 'service.home'
cert=sys.argv[4] if len(sys.argv)>4 else 'cert.pem'
address=sys.argv[5] if len(sys.argv)>5 else '127.0.0.1'
ctx=ssl.create_default_context(cafile=str(root/cert))
end=time.monotonic()+.35
while True:
 try:
  with ctx.wrap_socket(socket.create_connection((address,port),timeout=.1),server_hostname=host) as s:
   s.sendall(('GET / HTTP/1.0\r\nHost: '+host+'\r\n\r\n').encode());v=s.recv(1024)
   assert b'200 OK' in v,v
  break
 except (OSError,AssertionError):
  if time.monotonic()>=end:sys.exit(1)
  time.sleep(.01)
