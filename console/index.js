'use strict';
// The owner console, two mounts from one source.
//
//   Local:  serve({ root }) starts a small server on localhost that reads
//           console/services.json and the environment of the project at root.
//   Online: createConsole({ root, numbers }).handler is a (req, res) handler
//           the project mounts on a route behind its own owner sign-in.
//
// Both build the same view and render the same page.

const http = require('http');
const config = require('./config');
const render = require('./render');

function createConsole(options) {
  const opts = options || {};
  const root = opts.root || process.cwd();
  const mount = opts.mount || (opts.numbers ? 'online' : 'local');

  async function view() {
    const cfg = config.loadConfig(root);
    const env = opts.env || process.env;
    const isPresent = config.presence(root, env);
    let live = null;
    if (mount === 'online' && typeof opts.numbers === 'function' && cfg.numbers) {
      try { live = await opts.numbers(); } catch (e) { live = null; }
    }
    return config.buildView(cfg, { isPresent, env, live, mount });
  }

  async function html() {
    return render.renderPage(await view());
  }

  async function handler(req, res) {
    try {
      const page = await html();
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.setHeader('Cache-Control', 'no-store');
      res.end(page);
    } catch (e) {
      res.statusCode = 500;
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.end(`The console could not build the page: ${e.message}\n`);
    }
  }

  return { view, html, handler, root, mount };
}

function serve(options) {
  const opts = options || {};
  const port = Number(opts.port) || 7777;
  const host = '127.0.0.1';
  const console_ = createConsole({ root: opts.root, env: opts.env, mount: 'local' });
  const server = http.createServer((req, res) => {
    if (req.url === '/' || req.url.startsWith('/?') || req.url === '/index.html') return console_.handler(req, res);
    res.statusCode = 404;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.end('Only the console page is served here.\n');
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => resolve({ server, url: `http://${host}:${port}/` }));
  });
}

module.exports = { createConsole, serve };
