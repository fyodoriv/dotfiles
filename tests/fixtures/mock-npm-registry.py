"""Tiny read-only npm registry for bats tests.

Serves every `<name>-<version>.tgz` in ROOT (argv[1]) as a version of <name>.
Each tarball needs a `<tarball>.json` sidecar with its package.json fields
(bin, scripts). The server binds to a free port on 127.0.0.1 and prints it.

Usage: python3 -I tests/fixtures/mock-npm-registry.py <root> > port.txt &
"""
import base64, hashlib, http.server, json, os, sys

root = sys.argv[1]


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        port = self.server.server_address[1]
        name = self.path.lstrip('/').split('?')[0]
        if name.endswith('.tgz'):
            p = os.path.join(root, name)
            data = open(p, 'rb').read(); ctype = 'application/octet-stream'
        else:
            versions = {}
            for f in sorted(os.listdir(root)):
                if f.startswith(name + '-') and f.endswith('.tgz'):
                    v = f[len(name)+1:-4]
                    blob = open(os.path.join(root, f), 'rb').read()
                    meta = json.load(open(os.path.join(root, f + '.json')))
                    meta.update(name=name, version=v, dist={
                        'tarball': f'http://127.0.0.1:{port}/{f}',
                        'integrity': 'sha512-' + base64.b64encode(hashlib.sha512(blob).digest()).decode(),
                        'shasum': hashlib.sha1(blob).hexdigest()})
                    versions[v] = meta
            if not versions:
                self.send_response(404); self.end_headers(); return
            latest = sorted(versions, key=lambda s: [int(x) for x in s.split('.')])[-1]
            data = json.dumps({'name': name, 'dist-tags': {'latest': latest}, 'versions': versions}).encode()
            ctype = 'application/json'
        self.send_response(200); self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
s = http.server.HTTPServer(('127.0.0.1', 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
