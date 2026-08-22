'use strict';
(()=>{
  if(window.__RT79_VILLAGE_UI__) return;
  window.__RT79_VILLAGE_UI__=true;
  window.__RT80_VISUAL_BOOTSTRAP__=true;
  const loadStyle=(href,key)=>{if(document.querySelector(`link[data-${key}]`))return;const link=document.createElement('link');link.rel='stylesheet';link.href=href;link.setAttribute(`data-${key}`,'1');document.head.appendChild(link)};
  const loadScript=(src,key,ready)=>{if(window[ready]||document.querySelector(`script[data-${key}]`))return;const script=document.createElement('script');script.src=src;script.defer=true;script.setAttribute(`data-${key}`,'1');document.head.appendChild(script)};
  loadScript('reino-tribal-branding.js?v=1.0.1','reino-tribal-branding','__REINO_TRIBAL_BRANDING__');
  loadStyle('rt80-visual-system.css?v=80.0','rt80-visual');
  loadStyle('rt80-compat.css?v=80.5','rt80-compat');
  loadScript('rt80-visual-system.js?v=80.4','rt80-visual','__RT80_VISUAL_SYSTEM__');
  loadScript('rt80-admin-runtime.js?v=80.5','rt80-admin-runtime','__RT80_ADMIN_RUNTIME__');
  loadScript('rt81-security-runtime.js?v=81.3','rt81-security-runtime','__RT81_SECURITY_RUNTIME__');
  loadScript('rt83-world-combat.js?v=83.0','rt83-world-combat','__RT83_WORLD_COMBAT__');
  loadScript('rt84-world-actions.js?v=84.0','rt84-world-actions','__RT84_WORLD_ACTIONS__');
  loadScript('rt84-offer-consistency.js?v=84.1','rt84-offer-consistency','__RT84_OFFER_CONSISTENCY__');
  loadScript('rt85-auth-bridge.js?v=85.0','rt85-auth-bridge','__RT85_AUTH_BRIDGE__');
  loadScript('rt86-ai-director-ui.js?v=86.2','rt86-ai-director-ui','__RT86_AI_DIRECTOR_UI__');
  loadScript('rt86-ai-admin-nav.js?v=86.2','rt86-ai-admin-nav','__RT86_AI_ADMIN_NAV__');
  // IDs RT antigos abaixo permanecem apenas por compatibilidade técnica. A versão pública atual é Reino Tribal v1.0.1.
})();