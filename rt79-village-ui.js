'use strict';
(()=>{
  if(window.__RT79_VILLAGE_UI__) return;
  window.__RT79_VILLAGE_UI__=true;
  window.__RT80_VISUAL_BOOTSTRAP__=true;
  const ensureStyle=()=>{if(document.querySelector('link[data-rt80-visual]'))return;const link=document.createElement('link');link.rel='stylesheet';link.href='rt80-visual-system.css?v=80.0';link.dataset.rt80Visual='1';document.head.appendChild(link)};
  const ensureScript=()=>{if(window.__RT80_VISUAL_SYSTEM__||document.querySelector('script[data-rt80-visual]'))return;const script=document.createElement('script');script.src='rt80-visual-system.js?v=80.0';script.defer=true;script.dataset.rt80Visual='1';document.head.appendChild(script)};
  ensureStyle();ensureScript();
})();
