// Minimal static file server for the Flutter web build (no dependencies).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const [dir, port] = [path.resolve(process.argv[2]), Number(process.argv[3])];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css' };
http.createServer((req, res) => {
  let p = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  // Stay inside the web root: the root itself or a path below it (a bare prefix would also match a sibling).
  if (p !== dir && !p.startsWith(dir + path.sep)) { res.writeHead(403).end(); return; }
  if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) p = path.join(dir, 'index.html');
  res.writeHead(200, { 'content-type': types[path.extname(p)] ?? 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
}).listen(port, '127.0.0.1');
