'use strict';
(()=>{
  if(window.__RT79_VILLAGE_UI__) return;
  window.__RT79_VILLAGE_UI__=true;
  window.__RT80_VISUAL_BOOTSTRAP__=true;
  const loadStyle=(href,key)=>{if(document.querySelector(`link[data-${key}]`))return;const link=document.createElement('link');link.rel='stylesheet';link.href=href;link.setAttribute(`data-${key}`,'1');document.head.appendChild(link)};
  const ensureScript=()=>{if(window.__RT80_VISUAL_SYSTEM__||document.querySelector('script[data-rt80-visual]'))return;const script=document.createElement('script');script.src='rt80-visual-system.js?v=80.0';script.defer=true;script.dataset.rt80Visual='1';document.head.appendChild(script)};
  loadStyle('rt80-visual-system.css?v=80.0','rt80-visual');
  loadStyle('rt80-compat.css?v=80.0','rt80-compat');
  ensureScript();
})();
