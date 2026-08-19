'use strict';
(()=>{
  if(window.__RT81_SECURITY_RUNTIME__)return;
  window.__RT81_SECURITY_RUNTIME__=true;
  async function secureWorldDirectory(){
    if(typeof cloudRequest!=='function'||typeof CLOUD==='undefined'||!CLOUD?.session?.access_token)return [];
    const [worlds,directory]=await Promise.all([
      cloudRequest('/rest/v1/worlds?is_active=eq.true&status=eq.open&select=id,name,slug,settings,max_players,season_number,opened_at,created_at&order=created_at.asc'),
      cloudRequest('/rest/v1/rpc/rt81_world_directory',{method:'POST',body:{},timeoutMs:10000})
    ]);
    const rows=Array.isArray(directory)?directory:[];
    const byId=new Map(rows.map(x=>[String(x.world_id),x]));
    CLOUD.memberships=rows.filter(x=>x.joined).map(x=>({world_id:x.world_id,user_id:CLOUD.user?.id||null}));
    CLOUD.availableWorlds=(Array.isArray(worlds)?worlds:[]).map(w=>({...w,player_count:Number(byId.get(String(w.id))?.player_count)||0}));
    return CLOUD.availableWorlds;
  }
  if(typeof window.loadAvailableWorlds==='function')window.loadAvailableWorlds=secureWorldDirectory;
  setTimeout(()=>{
    if(typeof CLOUD==='undefined'||!CLOUD?.session?.access_token)return;
    secureWorldDirectory().then(()=>{try{if(typeof renderWorldSelector==='function')renderWorldSelector()}catch{}}).catch(e=>console.error('RT81 world directory',e));
  },0);
  window.RT81Security={version:'81.0',secureWorldDirectory};
})();
