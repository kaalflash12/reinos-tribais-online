'use strict';
window.REINO_TRIBAL_API_BASE = window.REINO_TRIBAL_API_BASE || 'https://reino-tribal-api.mestrederpg35.deno.net';
window.REINO_TRIBAL_BACKEND = Object.freeze({
  provider: 'turso',
  apiBase: window.REINO_TRIBAL_API_BASE,
  version: '1.0.4-turso-fix12',
  realtime: Object.freeze({
    enabled: true,
    path: '/ws',
    protocol: 1,
    client: 'rt88-v1'
  }),
  strategy: Object.freeze({
    enabled: true,
    path: '/api/strategy',
    client: 'rt89-v1'
  })
});

if (!document.querySelector('script[data-rt88-realtime-client]')) {
  const realtimeScript = document.createElement('script');
  realtimeScript.src = 'rt88-realtime-client.js?v=rt88-v1';
  realtimeScript.async = false;
  realtimeScript.dataset.rt88RealtimeClient = '1';
  document.head.appendChild(realtimeScript);
}

if (!document.querySelector('script[data-rt89-strategy-client]')) {
  const strategyScript = document.createElement('script');
  strategyScript.src = 'rt89-strategy-client.js?v=rt89-v1';
  strategyScript.async = false;
  strategyScript.dataset.rt89StrategyClient = '1';
  document.head.appendChild(strategyScript);
}
