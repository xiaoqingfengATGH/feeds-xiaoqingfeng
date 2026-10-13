import http.server, pathlib, json, urllib.request, subprocess, time

repo = pathlib.Path(__file__).resolve().parents[1]
assets = repo / 'docs/artifacts/luci-target-assets/www'

# router-side chroot uhttpd on 18992 (fixture already deployed by homedirect-luci-d1-fixture.py)
# This server serves the HTML shell + static assets on 18991 and proxies /ubus to 18992.

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        url = self.path.split('?')[0]
        if url == '/':
            sid = json.loads((repo / 'docs/artifacts/luci-fixture-session.json').read_text())['sid']
            body = b'''<!doctype html><html><body><div id="maincontent"><div id="view"></div></div><script>window._=s=>s;window.cbi_init=()=>{};</script><script src="/luci-static/resources/cbi.js"></script><script src="/luci-static/resources/luci.js"></script><script>
window.L=Object.create(LuCI.prototype);Object.assign(L.env,{base_url:'/luci-static/resources',resource:'/luci-static/resources',scriptname:'/cgi-bin/luci',cgi_base:'/cgi-bin',requestpath:[],documentroot:'/www',ubuspath:'/ubus',sessionid:__SID__,apply_display:0});L.loaded=true;window.result={};L.probeRPCBaseURL().then(()=>L.require('ui')).then(()=>L.require('view.homedirect.schema')).then(s=>{result.loader='PASS';result.hostname=s.hostname('a.example');}).catch(e=>{result.loader='FAIL';result.error=e.message;});
</script></body></html>'''.replace(b'__SID__', json.dumps(sid).encode())
        else:
            p = assets / url.lstrip('/')
            if url.startswith('/luci-static/resources/view/homedirect/'):
                p = repo / 'luci-app-homedirect/htdocs' / url.lstrip('/')
            if not p.is_file():
                self.send_error(404); return
            body = p.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html' if url == '/' else 'text/javascript')
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        req = urllib.request.Request('http://127.0.0.1:18992/ubus', data=body, headers={'Content-Type': 'application/json'})
        try:
            out = urllib.request.urlopen(req).read()
        except Exception as e:
            out = json.dumps({'error': str(e)}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(out)

http.server.ThreadingHTTPServer(('127.0.0.1', 18991), Handler).serve_forever()
