#!/usr/bin/env python3
"""Test-only fixed loopback TLS/backend probe; never production SAN authority."""
import pathlib, socket, ssl, sys, time
root=pathlib.Path(sys.argv[1]);port=int(sys.argv[2])
ctx=ssl.create_default_context(cafile=str(root/'cert.pem'))
end=time.monotonic()+.35
while True:
 try:
  with ctx.wrap_socket(socket.create_connection(('127.0.0.1',port),timeout=.1),server_hostname='service.home') as s:
   s.sendall(b'GET / HTTP/1.0\r\nHost: service.home\r\n\r\n');v=s.recv(1024)
   assert b'200 OK' in v,v
  break
 except (OSError,AssertionError):
  if time.monotonic()>=end:sys.exit(1)
  time.sleep(.01)
