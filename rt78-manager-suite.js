'use strict';
(()=>{
  if(window.__RT79_COMPAT_LOADER__) return;
  window.__RT79_COMPAT_LOADER__=true;
  const load=(src,flag)=>{
    if(window[flag]||document.querySelector(`script[src^="${src}"]`)) return;
    const s=document.createElement('script');
    s.src=`${src}?v=79.0`;
    s.defer=true;
    document.head.appendChild(s);
  };
  load('rt79-suite.js','__RT79_STRATEGY_SUITE__');
  load('rt79-admin-suite.js','__RT79_ADMIN_SUITE__');
  load('rt79-groups-addon.js','__RT79_GROUPS_ADDON__');
})();
