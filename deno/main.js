import reinoHandler from '../api/reino.js';
import adminHandler from '../api/admin.js';
import realtimeHandler from '../api/realtime.js';
import strategyHandler from '../api/strategy.js';

class CompatResponse {
  constructor() {
    this.statusCode = 200;
    this.headers = new Headers();
    this.body = null;
  }

  setHeader(name, value) {
    this.headers.set(name, String(value));
    return this;
  }

  status(code) {
    this.statusCode = Number(code) || 200;
    return this;
  }

  json(value) {
    this.headers.set('Content-Type', 'application/json; charset=utf-8');
    this.body = JSON.stringify(value);
    return this;
  }

  end(value = '') {
    this.body = value ?? '';
    return this;
  }

  toResponse() {
    const noBodyStatus = this.statusCode === 204 || this.statusCode === 205 || this.statusCode === 304;
    return new Response(noBodyStatus ? null : this.body, {
      status: this.statusCode,
      headers: this.headers,
    });
  }
}

async function compatRequest(request) {
  const headers = {};
  for (const [key, value] of request.headers.entries()) {
    headers[key.toLowerCase()] = value;
  }

  let body = null;
  if (!['GET', 'HEAD'].includes(request.method)) {
    const raw = await request.text();
    if (raw) {
      try { body = JSON.parse(raw); }
      catch { body = raw; }
    }
  }

  return {
    method: request.method,
    headers,
    body,
    url: request.url,
  };
}

async function runHandler(handler, request) {
  const req = await compatRequest(request);
  const res = new CompatResponse();
  await handler(req, res);
  return res.toResponse();
}

Deno.serve(async (request) => {
  const { pathname } = new URL(request.url);

  try {
    if (pathname === '/ws' || pathname === '/api/realtime/ws') return realtimeHandler(request);
    if (pathname === '/api/reino') return await runHandler(reinoHandler, request);
    if (pathname === '/api/admin') return await runHandler(adminHandler, request);
    if (pathname === '/api/strategy') return await runHandler(strategyHandler, request);
    if (pathname === '/' || pathname === '/health') {
      return new Response(JSON.stringify({
        ok: true,
        service: 'reino-tribal-api',
        runtime: 'deno-deploy',
        database: 'turso',
        realtime: true,
        websocket: '/ws',
        strategy: true,
        strategy_endpoint: '/api/strategy',
        version: '1.0.4-turso',
      }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff',
        },
      });
    }

    return new Response(JSON.stringify({ error: 'Rota não encontrada.' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
    });
  } catch (error) {
    console.error('reino-tribal-deno-runtime', error);
    return new Response(JSON.stringify({ error: 'Falha temporária do servidor.' }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    });
  }
});
