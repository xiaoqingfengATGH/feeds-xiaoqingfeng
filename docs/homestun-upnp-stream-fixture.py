#!/usr/bin/env python3
"""Numbered /hold HTTP chunks; loopback-only, bounded, no UPnP actions.

Reuse: run as the source backend, proxy with proxy_buffering off and no
limit_rate; run the regression's probe/validate against TLS before any mapping.
Never substitute recv event counts for application tick counts.
"""
import argparse
import itertools
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class StreamHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(3)
        self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path != '/hold':
            body = b'homestun-stream-fixture\n'
            self.send_response(200 if self.path == '/' else 404)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Transfer-Encoding', 'chunked')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Accel-Buffering', 'no')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.flush()
        start = time.monotonic()
        try:
            for number in itertools.count(1):
                if self.server.stop_event.is_set():
                    break
                payload = f'tick {number} {time.monotonic():.9f}\n'.encode('ascii')
                self.wfile.write(f'{len(payload):x}\r\n'.encode('ascii') + payload + b'\r\n')
                self.wfile.flush()
                if self.server.stop_event.wait(max(0, start + number*2-time.monotonic())):
                    break
            self.wfile.write(b'0\r\n\r\n')
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass
        finally:
            self.close_connection = True


class StreamServer(ThreadingHTTPServer):
    daemon_threads = False
    block_on_close = True

    def __init__(self, port):
        self.stop_event = threading.Event()
        super().__init__(('127.0.0.1', port), StreamHandler)

    def shutdown(self):
        self.stop_event.set()
        super().shutdown()


def make_server(port=0):
    return StreamServer(port)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18081)
    parser.add_argument('--ttl', type=int, default=60)
    args = parser.parse_args()
    if not 1 <= args.ttl <= 120:
        parser.error('ttl must be 1..120 seconds')
    with make_server(args.port) as server:
        timer = threading.Timer(args.ttl, server.shutdown)
        timer.start()
        print(f'loopback source 127.0.0.1:{server.server_port}; TTL={args.ttl}', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            server.stop_event.set()
        finally:
            server.stop_event.set()
            timer.cancel()
            timer.join(timeout=1)
