'use strict';
(()=>{
  if(window.__RT79_VILLAGE_UI__) return;
  window.__RT79_VILLAGE_UI__=true;
  window.__RT80_VISUAL_BOOTSTRAP__=true;
  const loadStyle=(href,key)=>{if(document.querySelector(`link[data-${key}]`))return;const link=document.createElement('link');link.rel='stylesheet';link.href=href;link.setAttribute(`data-${key}`,'1');document.head.appendChild(link)};
  const loadScript=(src,key,ready)=>{if(window[ready]||document.querySelector(`script[data-${key}]`))return;const script=document.createElement('script');script.src=src;script.defer=true;script.setAttribute(`data-${key}`,'1');document.head.appendChild(script)};
  loadStyle('rt80-visual-system.css?v=80.0','rt80-visual');
  loadStyle('rt80-compat.css?v=80.5','rt80-compat');
  loadScript('rt80-visual-system.js?v=80.4','rt80-visual','__RT80_VISUAL_SYSTEM__');
  loadScript('rt80-admin-runtime.js?v=80.5','rt80-admin-runtime','__RT80_ADMIN_RUNTIME__');
  // RT80.5 final validation marker: no runtime behavior change.
})();
