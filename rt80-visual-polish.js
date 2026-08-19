'use strict';
(()=>{
  if(window.__RT80_VISUAL_POLISH__) return;
  window.__RT80_VISUAL_POLISH__=true;
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
  let pending=false;
  const VIEW_META={
    overview:['🏰','Aldeia'],buildings:['🛠','Edifícios'],map:['🗺','Mapa'],commands:['➤','Comandos'],hero:['⚜','Paladino']
  };
  function activeView(){return $('.side-nav button.active[data-view]')?.dataset.view||document.body.dataset.rt80View||'overview'}
  function syncView(){const v=activeView();document.body.dataset.rt80View=v;$$('.rt80-mobile-dock button[data-rt80-view]').forEach(b=>b.classList.toggle('active',b.dataset.rt80View===v))}
  function compactStrategy(){
    const top=$('.topbar-inner');if(!top)return;
    if(!$('.rt80-strategy-compact',top)){
      const b=document.createElement('button');b.type='button';b.className='rt80-strategy-compact';b.textContent='Estratégia';b.setAttribute('aria-label','Abrir Central Estratégica RT80');b.addEventListener('click',()=>window.RT79?.open?.());
      const target=top.querySelector('[data-cloud-login],.rt55-connect,.cloud-connect,.brand-account')||null;
      target?top.insertBefore(b,target):top.appendChild(b);
    }
  }
  function mobileDock(){
    if($('.rt80-mobile-dock'))return;
    const dock=document.createElement('nav');dock.className='rt80-mobile-dock';dock.setAttribute('aria-label','Navegação principal móvel');
    for(const [view,[icon,label]] of Object.entries(VIEW_META)){
      const b=document.createElement('button');b.type='button';b.dataset.rt80View=view;b.innerHTML=`<span>${icon}</span><b>${label}</b>`;
      b.addEventListener('click',()=>{
        const original=$(`.side-nav button[data-view="${CSS.escape(view)}"]`);
        if(original) original.click();
        else if(view==='overview') $('.side-nav button[data-view="village"]')?.click();
        syncView();
      });dock.appendChild(b)
    }
    document.body.appendChild(dock);syncView();
  }
  function visibleBrandingCleanup(){
    const kicker=$('.rt55-kicker');if(kicker&&/RT7[89]/.test(kicker.textContent||''))kicker.textContent=(kicker.textContent||'').replace(/RT7[89](?:\.1)?/g,'RT80');
    $$('.rt79-scene-badge').forEach(n=>n.remove());
    const title=document.title.replace(/RT79(?:\.1)?/g,'RT80');if(title!==document.title)document.title=title;
  }
  function favicon(){if(document.querySelector('link[data-rt80-favicon]'))return;const l=document.createElement('link');l.rel='icon';l.href='assets/icons/reinos_tribais_icon.png';l.dataset.rt80Favicon='1';document.head.appendChild(l)}
  function labelTop(){const chip=$('.rt80-view-chip');if(chip)chip.remove();const title=$('.panel-title');if(!title)return;const v=activeView();const meta=VIEW_META[v];if(!meta)return;const c=document.createElement('span');c.className='rt80-view-chip';c.textContent=`RT80 • ${meta[1]}`;title.appendChild(c)}
  function ensure(){compactStrategy();mobileDock();visibleBrandingCleanup();favicon();syncView();labelTop()}
  function schedule(){if(pending)return;pending=true;requestAnimationFrame(()=>{pending=false;try{ensure()}catch(e){console.error('RT80 polish',e)}})}
  new MutationObserver(schedule).observe(document.body||document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','data-view']});
  document.addEventListener('click',schedule,true);window.addEventListener('resize',schedule,{passive:true});setInterval(schedule,3000);schedule();
})();
