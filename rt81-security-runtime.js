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
  function markRemoteProjection(){
    if(typeof window.buildRemoteVillage!=='function'||window.buildRemoteVillage.__rt81Wrapped)return;
    const original=window.buildRemoteVillage;
    const wrapped=function(row){const v=original(row);if(v&&row?.public_visual_projection){v._publicVisualProjection=true;v._buildingIntelApproximate=true}return v};
    wrapped.__rt81Wrapped=true;wrapped.__rt81Original=original;window.buildRemoteVillage=wrapped;
  }
  function annotateProjectedTarget(){
    const form=document.querySelector('#attack-form[data-target-id]');if(!form||form.dataset.rt81IntelNotice)return;
    const id=form.dataset.targetId,v=window.state?.villages?.[id];
    if(!v?._publicVisualProjection)return;
    form.dataset.rt81IntelNotice='1';
    const note=document.createElement('div');note.className='notice';note.dataset.rt81ProjectionNotice='1';
    note.innerHTML='<b>Inteligência protegida</b><br><span class="small">A aparência desta aldeia é uma projeção visual calculada pelos pontos públicos. Níveis reais de muralha, edifícios, tropas e recursos não são enviados ao cliente adversário. Use espionagem, relatórios e a Torre de Vigia para obter informação real.</span>';
    form.prepend(note);
  }
  if(typeof window.loadAvailableWorlds==='function')window.loadAvailableWorlds=secureWorldDirectory;
  markRemoteProjection();
  const mo=new MutationObserver(()=>{markRemoteProjection();annotateProjectedTarget()});
  mo.observe(document.documentElement,{childList:true,subtree:true});
  setTimeout(()=>{
    markRemoteProjection();annotateProjectedTarget();
    if(typeof CLOUD==='undefined'||!CLOUD?.session?.access_token)return;
    secureWorldDirectory().then(()=>{try{if(typeof renderWorldSelector==='function')renderWorldSelector()}catch{}}).catch(e=>console.error('RT81 world directory',e));
  },0);
  window.RT81Security={version:'81.1',secureWorldDirectory,markRemoteProjection,annotateProjectedTarget};
})();
