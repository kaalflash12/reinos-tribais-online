'use strict';
(()=>{
  if(window.__RT79_VILLAGE_UI__) return;
  window.__RT79_VILLAGE_UI__=true;
  const CAT={
    production:['timber','clay','iron','farm','warehouse'],
    military:['barracks','stable','garage','smith','rally','academy'],
    civic:['main','market','statue','church','first_church','watchtower','hide'],
    defense:['wall']
  };
  const label={production:'Produção',military:'Militar',civic:'Cívico',defense:'Defesa'};
  let active='all';
  const $=(s,r=document)=>r.querySelector(s);
  function currentScene(){return $('.game-shell .village-scene');}
  function visible(el){return !!el && getComputedStyle(el).display!=='none' && getComputedStyle(el).visibility!=='hidden';}
  function setCategory(cat){
    active=cat;
    const scene=currentScene();if(!scene)return;
    scene.dataset.rt79Category=cat;
    scene.querySelectorAll('[data-village-building]').forEach(el=>{
      const key=el.dataset.villageBuilding||'';
      const on=cat==='all'||(CAT[cat]||[]).includes(key);
      el.classList.toggle('rt79-dim',!on);
      el.classList.toggle('rt79-focus',on&&cat!=='all');
    });
    document.querySelectorAll('[data-rt79-vcat]').forEach(b=>b.classList.toggle('active',b.dataset.rt79Vcat===cat));
  }
  function wallTier(scene){const img=scene.querySelector('[data-village-building="wall"]');return Math.max(0,Math.min(4,Number(img?.dataset.villageTier||0)));}
  function ensureSceneDecor(scene){
    if(!scene.querySelector('.rt79-road-net')){
      const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('class','rt79-road-net');svg.setAttribute('viewBox','0 0 1671 941');svg.setAttribute('aria-hidden','true');
      svg.innerHTML='<path d="M820 465 C710 440 625 388 540 325 M823 468 C932 427 1050 390 1175 322 M820 470 C810 590 750 665 690 745 M825 470 C935 548 1060 600 1210 650 M820 465 C750 360 730 255 760 165"/><path class="minor" d="M540 325 C430 340 330 420 260 505 M1175 322 C1320 330 1450 285 1530 190 M690 745 C570 745 450 710 350 675 M1210 650 C1360 650 1465 600 1540 535"/>';
      scene.appendChild(svg);
    }
    let ring=scene.querySelector('.rt79-wall-perimeter');if(!ring){ring=document.createElement('div');ring.className='rt79-wall-perimeter';ring.setAttribute('aria-hidden','true');scene.appendChild(ring)}
    ring.dataset.tier=String(wallTier(scene));
    let badge=scene.querySelector('.rt79-scene-badge');if(!badge){badge=document.createElement('div');badge.className='rt79-scene-badge';scene.appendChild(badge)}
    badge.textContent='RT79 • ALDEIA VIVA • 19 EDIFÍCIOS';
  }
  function ensureToolbar(scene){
    const center=scene.closest('.rt22-center')||scene.parentElement;if(!center)return;
    let bar=center.querySelector('.rt79-village-toolbar');
    if(!bar){
      bar=document.createElement('div');bar.className='rt79-village-toolbar';
      bar.innerHTML='<div class="rt79-vtitle"><b>ALDEIA 2.0</b><span>clique diretamente nos edifícios</span></div><div class="rt79-vcats"><button data-rt79-vcat="all" class="active">Todos</button>'+Object.keys(CAT).map(k=>`<button data-rt79-vcat="${k}">${label[k]}</button>`).join('')+'</div><div class="rt79-vactions"><button data-rt79-index>☷ Índice</button><button data-rt79-panels>▤ Painéis</button><button data-rt79-strategy>⚔ Estratégia</button></div>';
      center.insertBefore(bar,scene);
    }
  }
  function ensure(){
    const scene=currentScene();
    const on=visible(scene);
    document.body.classList.toggle('rt79-village-active',on);
    if(!on)return;
    ensureSceneDecor(scene);ensureToolbar(scene);setCategory(active);
    const old=scene.querySelector('.rt75-scene-build');if(old)old.style.display='none';
  }
  document.addEventListener('click',e=>{
    const cat=e.target.closest('[data-rt79-vcat]');if(cat){setCategory(cat.dataset.rt79Vcat);return}
    if(e.target.closest('[data-rt79-index]')){document.body.classList.toggle('rt79-show-index');return}
    if(e.target.closest('[data-rt79-panels]')){document.body.classList.toggle('rt79-show-panels');return}
    if(e.target.closest('[data-rt79-strategy]')){window.RT79?.open?.();return}
  },true);
  let inspector=null;
  document.addEventListener('mouseover',e=>{const cell=e.target.closest('.map-cell.village');if(!cell)return;if(!inspector){inspector=document.createElement('div');inspector.className='rt79-map-inspector';document.body.appendChild(inspector)}const coord=cell.querySelector('.map-coord')?.textContent||'';const pts=cell.querySelector('.map-points')?.textContent||'';const text=(cell.getAttribute('title')||cell.textContent||'').replace(/\s+/g,' ').trim();inspector.innerHTML=`<b>${text||'Aldeia'}</b><span>${coord}</span><span>${pts}</span>`;inspector.classList.add('show')},true);
  document.addEventListener('mousemove',e=>{if(inspector?.classList.contains('show')){inspector.style.left=Math.min(innerWidth-260,e.clientX+16)+'px';inspector.style.top=Math.min(innerHeight-110,e.clientY+16)+'px'}},true);
  document.addEventListener('mouseout',e=>{if(e.target.closest('.map-cell.village'))inspector?.classList.remove('show')},true);
  const css=document.createElement('style');css.id='rt79-village-ui-css';css.textContent=`
  body.rt79-village-active .game-shell .rt22-dashboard{grid-template-columns:minmax(0,1fr)!important;max-width:1500px!important;margin:auto!important;gap:0!important}
  body.rt79-village-active .game-shell .rt22-left,body.rt79-village-active .game-shell .rt22-right,body.rt79-village-active .game-shell .rt22-map-box{display:none!important}
  body.rt79-village-active .game-shell .rt22-center{width:100%!important;max-width:1500px!important;margin:auto!important;overflow:visible!important}
  body.rt79-village-active .game-shell .rt22-village-head{margin:0 0 6px!important;border-radius:8px!important;padding:7px 12px!important;display:flex!important;justify-content:space-between!important;gap:12px!important}
  body.rt79-village-active .game-shell .rt24-village-hud{position:absolute!important;z-index:30!important;right:18px!important;top:94px!important;width:min(330px,31vw)!important;background:#10150edb!important;border:1px solid #8a7138!important;border-radius:8px!important;padding:7px 9px!important;color:#efe0b5!important;backdrop-filter:blur(3px)!important}
  body.rt79-village-active .game-shell .village-scene{width:100%!important;max-width:none!important;border:2px solid #392910!important;border-radius:10px!important;box-shadow:0 14px 36px #0008,inset 0 0 42px #1118!important;background:#1c2a18!important}
  body.rt79-village-active .game-shell .rt25-building-index{display:none!important;grid-template-columns:repeat(auto-fit,minmax(170px,1fr))!important;max-height:260px!important;overflow:auto!important;margin:8px 0!important;padding:8px!important;background:#10140eee!important;border:1px solid #5b4b2c!important;border-radius:8px!important}
  body.rt79-village-active.rt79-show-index .game-shell .rt25-building-index{display:grid!important}
  body.rt79-village-active.rt79-show-panels .game-shell .rt22-left,body.rt79-village-active.rt79-show-panels .game-shell .rt22-right{display:block!important;position:fixed!important;top:110px!important;bottom:20px!important;width:270px!important;overflow:auto!important;z-index:90!important;box-shadow:0 12px 40px #000b!important}
  body.rt79-village-active.rt79-show-panels .game-shell .rt22-left{left:12px!important}body.rt79-village-active.rt79-show-panels .game-shell .rt22-right{right:12px!important}
  .rt79-village-toolbar{display:grid;grid-template-columns:auto 1fr auto;align-items:center;gap:10px;margin:0 0 7px;padding:7px 9px;background:linear-gradient(180deg,#1d2418,#10140e);border:1px solid #62502d;border-radius:8px;color:#ead8a5;font:12px system-ui;box-shadow:0 4px 12px #0005}
  .rt79-vtitle{display:grid;line-height:1.05}.rt79-vtitle b{color:#efc961;font:800 14px Georgia}.rt79-vtitle span{color:#9f967b;font-size:10px}.rt79-vcats,.rt79-vactions{display:flex;gap:5px;flex-wrap:wrap}.rt79-vactions{justify-content:flex-end}.rt79-village-toolbar button{border:1px solid #65522c;background:#272319;color:#d9c89b;border-radius:5px;padding:6px 9px;font-weight:700}.rt79-village-toolbar button.active{background:#75602d;color:#fff0b2;border-color:#ad8d43}
  .village-scene [data-village-building].rt79-dim{opacity:.24!important;filter:grayscale(.45) brightness(.65)!important}.village-scene [data-village-building].rt79-focus{filter:drop-shadow(0 0 8px #e7c45e)!important}.village-scene .rt60-village-hitbox.rt79-focus{outline:2px solid #f0cc64!important;background:#f0cc6414!important}.village-scene .rt60-village-hitbox.rt79-dim{pointer-events:none!important}
  .rt79-road-net{position:absolute;inset:0;width:100%;height:100%;z-index:2;pointer-events:none;opacity:.34}.rt79-road-net path{fill:none;stroke:#745f3d;stroke-width:19;stroke-linecap:round;stroke-dasharray:2 2;filter:drop-shadow(0 2px 1px #1b1308)}.rt79-road-net path.minor{stroke-width:11;opacity:.65}
  .rt79-wall-perimeter{position:absolute;inset:4.8% 4.2% 7.3% 4.2%;z-index:510;pointer-events:none;border-radius:34% 39% 31% 36% / 28% 27% 34% 32%;opacity:0;box-shadow:inset 0 0 0 1px #0008,0 3px 8px #0008}.rt79-wall-perimeter[data-tier="1"]{opacity:.42;border:3px dashed #6f624d}.rt79-wall-perimeter[data-tier="2"]{opacity:.58;border:5px double #7b6c56}.rt79-wall-perimeter[data-tier="3"]{opacity:.72;border:7px ridge #7c6a50}.rt79-wall-perimeter[data-tier="4"]{opacity:.88;border:9px ridge #8a7556;box-shadow:inset 0 0 0 3px #382d20,0 4px 10px #000a}.rt79-wall-perimeter:before,.rt79-wall-perimeter:after{content:'';position:absolute;width:20px;height:20px;border:3px solid #604f37;background:#7c6849;transform:rotate(45deg);opacity:inherit}.rt79-wall-perimeter:before{left:7%;top:10%}.rt79-wall-perimeter:after{right:7%;bottom:10%}
  .rt79-scene-badge{position:absolute;left:8px;bottom:7px;z-index:900;background:#10150ee8;color:#eacb70;border:1px solid #82692f;border-radius:5px;padding:4px 7px;font:800 10px system-ui;pointer-events:none}
  .rt79-map-inspector{display:none;position:fixed;z-index:1000004;width:240px;background:#11160ff2;color:#eddfba;border:1px solid #786134;border-radius:7px;padding:8px;box-shadow:0 8px 24px #000a;font:12px system-ui;pointer-events:none}.rt79-map-inspector.show{display:grid;gap:3px}.rt79-map-inspector b{color:#efc766}
  @media(max-width:820px){.rt79-village-toolbar{grid-template-columns:1fr}.rt79-vactions{justify-content:flex-start}body.rt79-village-active .game-shell .rt24-village-hud{position:relative!important;right:auto!important;top:auto!important;width:100%!important;margin:0 0 5px!important}.rt79-road-net{opacity:.2}.rt79-wall-perimeter{inset:5% 3% 7% 3%}}
  `;document.head.appendChild(css);
  new MutationObserver(()=>queueMicrotask(ensure)).observe(document.documentElement,{childList:true,subtree:true});setInterval(ensure,1800);ensure();
})();
