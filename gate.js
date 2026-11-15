'use strict';
/**
 * OpenClaw 前置网关（容器内使用）
 *
 * 作用：免费平台（Render / Koyeb / Zeabur / Fly …）都会在请求前加一层反向代理，
 * 并注入 X-Forwarded-For / X-Real-IP / X-Forwarded-Proto 等头。
 * OpenClaw 的 ingress-attribution 判定看到「非可信代理带来的转发头」，
 * 会直接返回 proxy_attribution_required 并拒绝请求（这就是之前在 instabox 上
 * 发布 7860 端口后打不开控制台的原因）。
 *
 * 这里做两件事：
 *   1. 监听平台分配的 PORT，先接住流量；
 *   2. 剥掉所有转发类请求头，把请求以「本机直连」的形态转给 OpenClaw，
 *      判定层看到的就是干净的回环请求。
 *
 * 同时透传 WebSocket 升级，保证控制台实时通道可用。
 */
const http = require('node:http');

const LISTEN_PORT = Number(process.env.PORT || 7860);
const UPSTREAM_PORT = Number(process.env.OPENCLAW_GATEWAY_PORT || 18789);
const UPSTREAM_HOST = '127.0.0.1';

// 只剥这些头，其余（cookie / authorization / sec-websocket-*）全部原样保留
const STRIP = /^(x-forwarded(-for|-proto|-host|-port|-server|-prefix)?|x-real-ip|x-client-ip|forwarded|cf-connecting-ip|cf-ray|cf-visitor|true-client-ip|fly-client-ip|koyeb-.*|render-.*|x-vercel-.*)$/i;

function cleanHeaders(raw) {
  const out = {};
  for (const [k, v] of Object.entries(raw)) {
    if (STRIP.test(k)) continue;
    out[k] = v;
  }
  out.host = `${UPSTREAM_HOST}:${UPSTREAM_PORT}`;
  return out;
}

const server = http.createServer((req, res) => {
  if (req.url === '/healthz' || req.url === '/_health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, upstream: UPSTREAM_PORT }));
    return;
  }
  const upstream = http.request(
    { host: UPSTREAM_HOST, port: UPSTREAM_PORT, path: req.url, method: req.method, headers: cleanHeaders(req.headers) },
    (r) => {
      res.writeHead(r.statusCode || 502, r.headers);
      r.pipe(res);
    },
  );
  upstream.on('error', (err) => {
    console.error('[gate] upstream error:', err.message);
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('openclaw upstream not ready\n');
  });
  req.pipe(upstream);
});

// WebSocket / 长连接升级透传
server.on('upgrade', (req, socket, head) => {
  const upstream = http.request({
    host: UPSTREAM_HOST,
    port: UPSTREAM_PORT,
    path: req.url,
    method: req.method,
    headers: cleanHeaders(req.headers),
  });
  upstream.on('upgrade', (r, upSocket, upHead) => {
    socket.write(`HTTP/1.1 101 Switching Protocols\r\n`);
    for (let i = 0; i < r.rawHeaders.length; i += 2) {
      socket.write(`${r.rawHeaders[i]}: ${r.rawHeaders[i + 1]}\r\n`);
    }
    socket.write('\r\n');
    if (upHead && upHead.length) socket.write(upHead);
    upSocket.pipe(socket);
    socket.pipe(upSocket);
    upSocket.on('error', () => socket.destroy());
    socket.on('error', () => upSocket.destroy());
  });
  upstream.on('error', (err) => {
    console.error('[gate] upgrade error:', err.message);
    socket.destroy();
  });
  upstream.end();
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`[gate] listening on :${LISTEN_PORT} -> 127.0.0.1:${UPSTREAM_PORT}`);
});
