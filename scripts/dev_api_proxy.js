#!/usr/bin/env node
/**
 * Local CORS-friendly proxy for Flutter web → live (or any) API.
 *
 * Chrome cannot call https://api.bldtrack.ai from a localhost origin (CORS).
 * This proxy adds CORS and forwards to the live API.
 *
 * IMPORTANT: bind 0.0.0.0 and always use http://127.0.0.1:PORT in Flutter so
 * Chrome does not hit IPv6 ::1 (which fails if only IPv4 is listening).
 *
 * Usage:
 *   node scripts/dev_api_proxy.js
 *   PROXY_TARGET=https://api.bldtrack.ai PROXY_PORT=8787 node scripts/dev_api_proxy.js
 *
 * Then:
 *   flutter run -d chrome --web-hostname=127.0.0.1 \
 *     --dart-define=API_BASE_URL=http://127.0.0.1:8787
 */
'use strict';

const http = require('http');
const https = require('https');
const { URL } = require('url');

const TARGET = (process.env.PROXY_TARGET || 'https://api.bldtrack.ai').replace(/\/$/, '');
const PORT = parseInt(process.env.PROXY_PORT || '8787', 10);
const targetUrl = new URL(TARGET);
const upstream = targetUrl.protocol === 'https:' ? https : http;

function setCors(req, res) {
  const origin = req.headers.origin || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    req.headers['access-control-request-headers'] ||
      'Content-Type, Authorization, Accept, X-Requested-With',
  );
  res.setHeader('Access-Control-Max-Age', '86400');
}

const server = http.createServer((req, res) => {
  setCors(req, res);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const path = req.url || '/';
  const headers = { ...req.headers, host: targetUrl.host };
  // Do not forward browser-only hop-by-hop headers that break HTTPS upstream.
  delete headers.origin;
  delete headers.referer;
  delete headers['accept-encoding'];
  delete headers.connection;
  delete headers['content-length'];
  delete headers['transfer-encoding'];

  const options = {
    hostname: targetUrl.hostname,
    port: targetUrl.port || (targetUrl.protocol === 'https:' ? 443 : 80),
    path,
    method: req.method,
    headers,
  };

  const proxyReq = upstream.request(options, (proxyRes) => {
    setCors(req, res);
    // Strip upstream CORS so our headers win.
    const outHeaders = { ...proxyRes.headers };
    delete outHeaders['access-control-allow-origin'];
    delete outHeaders['access-control-allow-credentials'];
    delete outHeaders['access-control-allow-headers'];
    delete outHeaders['access-control-allow-methods'];
    res.writeHead(proxyRes.statusCode || 502, outHeaders);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', (err) => {
    setCors(req, res);
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: false, message: `Proxy error: ${err.message}` }));
  });

  req.pipe(proxyReq);
});

// Bind all IPv4 interfaces. Flutter must use 127.0.0.1 (not localhost) to avoid ::1.
server.listen(PORT, '0.0.0.0', () => {
  console.log(`BldTrack live API proxy listening on 0.0.0.0:${PORT}`);
  console.log(`  Upstream: ${TARGET}`);
  console.log('Run Flutter web with:');
  console.log(
    `  flutter run -d chrome --web-hostname=127.0.0.1 --dart-define=API_BASE_URL=http://127.0.0.1:${PORT}`,
  );
});
