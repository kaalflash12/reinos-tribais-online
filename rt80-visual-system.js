'use strict';
(()=>{
  if(window.__RT80_VISUAL_SYSTEM__) return;
  window.__RT80_VISUAL_SYSTEM__=true;
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
  const BUILDINGS={main:'Edifício Principal',barracks:'Quartel',stable:'Estábulo',garage:'Oficina',smith:'Ferreiro',rally:'Praça de Reunião',academy:'Academia',market:'Mercado',timber:'Bosque / Madeira',clay:'Poço de Argila',iron:'Mina de Ferro',farm:'Fazenda',warehouse:'Armazém',wall:'Muralha',statue:'Estátua / Paladino',church:'Igreja',first_church:'Primeira Igreja',watchtower:'Torre de Vigia',hide:'Esconderijo'};
  const GROUP={main:'Centro',barracks:'Militar',stable:'Militar',garage:'Militar',smith:'Militar',rally:'Militar',academy:'Militar',market:'Economia',timber:'Produção',clay:'Produção',iron:'Produção',farm:'Produção',warehouse:'Economia',wall:'Defesa',statue:'Cívico',church:'Cívico',first_church:'Cívico',watchtower:'Defesa',hide:'Defesa'};
  let pending=false,inspector=null;
  function visible(el){if(!el)return false;const s=getComputedStyle(el);return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity)!==0}
  function currentMode(){const scene=$('.game-shell .village-scene');if(visible(scene))return'village';const map=$('.game-shell .map-wrap, .game-shell .rt17-map-screen, .game-shell .rt17-map-canvas');if(visible(map))return'map';return $('.game-shell')?'page':'start'}
  function renderedView(){
    if(visible($('.rt64-building-overview-head')))return'buildings';
    if(visible($('.rt19-paladin-hero')))return'hero';
    if(visible($('.rt17-map-screen,.map-wrap')))return'map';
    if(visible($('[data-research-tree],.research-tree,.rt19-research-grid')))return'research';
    if(visible($('[data-market-screen],.market-screen,.rt19-market-grid')))return'market';
    return'';
  }
  function currentView(){return renderedView()||$('.side-nav button.active[data-view]')?.dataset.view||$('.rt17-nav-main button.active[data-view]')?.dataset.view||document.body.dataset.rt80RequestedView||'overview'}
  function applyMode(){const mode=currentMode(),view=currentView();document.body.classList.add('rt80-visual-ready');document.body.classList.toggle('rt80-village-mode',mode==='village');document.body.classList.toggle('rt80-map-mode',mode==='map');document.body.classList.toggle('rt80-page-mode',mode==='page');document.body.dataset.rt80Mode=mode;document.body.dataset.rt80View=view}
  function categoryKeys(){return{production:['timber','clay','iron','farm','warehouse'],military:['barracks','stable','garage','smith','rally','academy'],civic:['main','market','statue','church','first_church'],defense:['wall','watchtower','hide']}}
  function setVillageCategory(cat){const scene=$('.village-scene');if(!scene)return;const groups=categoryKeys();scene.dataset.rt79Category=cat;$$('[data-village-building]',scene).forEach(el=>{const key=el.dataset.villageBuilding||'';const on=cat==='all'||(groups[cat]||[]).includes(key);el.classList.toggle('rt79-dim',!on);el.classList.toggle('rt79-focus',on&&cat!=='all')});$$('[data-rt79-vcat]').forEach(b=>b.classList.toggle('active',b.dataset.rt79Vcat===cat))}
  function ensureVillageToolbar(){const scene=$('.game-shell .village-scene');if(!visible(scene))return;const center=scene.closest('.rt22-center')||scene.parentElement;if(!center)return;let bar=$('.rt80-village-toolbar',center)||$('.rt79-village-toolbar',center);if(!bar){bar=document.createElement('div');bar.className='rt79-village-toolbar rt80-village-toolbar';bar.innerHTML='<div class="rt79-vtitle"><b>ALDEIA</b><span>cena estratégica • edifícios clicáveis</span></div><div class="rt79-vcats"><button data-rt79-vcat="all" class="active">Todos</button><button data-rt79-vcat="production">Produção</button><button data-rt79-vcat="military">Militar</button><button data-rt79-vcat="civic">Cívico</button><button data-rt79-vcat="defense">Defesa</button></div><div class="rt79-vactions"><button data-rt79-index>☷ Edifícios</button><button data-rt79-panels>▤ Informações</button><button data-rt79-strategy>⚔ Estratégia</button></div>';center.insertBefore(bar,scene.nextSibling)}else{bar.classList.add('rt80-village-toolbar')}scene.querySelector('.rt79-road-net')?.remove();scene.querySelector('.rt79-wall-perimeter')?.remove();scene.querySelector('.rt79-scene-badge')?.remove()}
  function ensureMapToolbar(){const wrap=$('.game-shell .map-wrap');if(!visible(wrap))return;if(wrap.previousElementSibling?.classList?.contains('rt80-map-toolbar'))return;const bar=document.createElement('div');bar.className='rt80-map-toolbar';bar.innerHTML='<strong>MAPA DO MUNDO</strong><span>arraste/role para explorar</span><button class="rt80-control" data-rt80-center-map>Centralizar</button><button class="rt80-control" data-rt80-toggle-map-rail>Painéis</button>';wrap.parentNode.insertBefore(bar,wrap)}
  function ensureInspector(){if(inspector)return inspector;inspector=document.createElement('div');inspector.className='rt80-building-inspector';inspector.setAttribute('role','tooltip');document.body.appendChild(inspector);return inspector}
  function buildingTarget(target){return target?.closest?.('[data-village-building], .rt60-village-hitbox[data-building], .rt60-village-hitbox[data-village-building]')||null}
  function showBuildingInspector(target,x,y){const el=buildingTarget(target);if(!el)return;const key=el.dataset.villageBuilding||el.dataset.building||el.getAttribute('data-open-building')||'';if(!key)return;const scene=$('.village-scene');const art=scene?.querySelector(`[data-village-building="${CSS.escape(key)}"]`);const tier=art?.dataset.villageTier??el.dataset.villageTier??'';const level=art?.dataset.villageLevel??el.dataset.level??'';const tip=ensureInspector();tip.innerHTML=`<strong>${BUILDINGS[key]||key}</strong><small>${GROUP[key]||'Edifício'}</small><span class="tier">${level!==''?`Nível ${level}`:tier!==''?`Estágio visual ${tier}`:'Clique para abrir'}</span>`;tip.classList.add('show');moveInspector(x,y)}
  function moveInspector(x,y){if(!inspector?.classList.contains('show'))return;inspector.style.left=Math.max(8,Math.min(innerWidth-260,x+16))+'px';inspector.style.top=Math.max(8,Math.min(innerHeight-100,y+16))+'px'}
  function hideInspector(){inspector?.classList.remove('show')}
  function centerMap(){const wrap=$('.map-wrap');if(!wrap)return;wrap.scrollTo({left:Math.max(0,(wrap.scrollWidth-wrap.clientWidth)/2),top:Math.max(0,(wrap.scrollHeight-wrap.clientHeight)/2),behavior:'smooth'})}
  function ensureAriaAndLabels(){$$('.side-nav button[data-view]').forEach(btn=>{if(!btn.getAttribute('aria-label'))btn.setAttribute('aria-label',(btn.textContent||btn.dataset.view||'').trim())});$$('.map-cell.village').forEach(cell=>{if(!cell.getAttribute('tabindex'))cell.setAttribute('tabindex','0')});$$('[data-village-building]').forEach(el=>{const key=el.dataset.villageBuilding;if(key&&!el.getAttribute('aria-label'))el.setAttribute('aria-label',BUILDINGS[key]||key)})}
  function normalizeLegacyText(){
    const root=$('.game-shell');if(!root)return;
    const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode(node){const p=node.parentElement;if(!p||['SCRIPT','STYLE','TEXTAREA','OPTION'].includes(p.tagName))return NodeFilter.FILTER_REJECT;const t=node.nodeValue||'';return /(RT79(?:\.1)?|RT76|Versão\s+79)/.test(t)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT}});
    const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
    nodes.forEach(node=>{let t=node.nodeValue||'';t=t.replace(/Versão\s+79\b/g,'Versão RT80').replace(/\bRT79\.1\b/g,'RT80').replace(/\bRT79\b/g,'RT80').replace(/\bRT76\b/g,'RT80');node.nodeValue=t});
  }
  function cleanLegacyVisuals(){
    $$('.rt17-nav-main,.rt17-nav').forEach(n=>n.classList.add('rt80-legacy-nav'));
    $$('.village-scene *').forEach(n=>{if(n.children.length===0&&/RT79(?:\.1)?\s*•\s*aldeia ativa/i.test((n.textContent||'').trim()))n.remove()});
    normalizeLegacyText();
    const title=document.title.replace(/RT79(?:\.1)?/g,'RT80').replace(/RT76/g,'RT80');if(title!==document.title)document.title=title;
    if(!document.querySelector('link[data-rt80-favicon]')){const l=document.createElement('link');l.rel='icon';l.href='assets/icons/reinos_tribais_icon.png';l.dataset.rt80Favicon='1';document.head.appendChild(l)}
  }
  function ensure(){applyMode();ensureVillageToolbar();ensureMapToolbar();ensureAriaAndLabels();cleanLegacyVisuals()}
  function schedule(){if(pending)return;pending=true;requestAnimationFrame(()=>{pending=false;try{ensure()}catch(err){console.error('RT80 visual ensure',err)}})}
  document.addEventListener('click',e=>{const view=e.target.closest('[data-view]')?.dataset.view;if(view)document.body.dataset.rt80RequestedView=view;const cat=e.target.closest('[data-rt79-vcat]');if(cat){setVillageCategory(cat.dataset.rt79Vcat);return}if(e.target.closest('[data-rt79-index]')){document.body.classList.toggle('rt79-show-index');return}if(e.target.closest('[data-rt79-panels]')){document.body.classList.toggle('rt79-show-panels');return}if(e.target.closest('[data-rt79-strategy]')){window.RT79?.open?.();return}if(e.target.closest('[data-rt80-center-map]')){centerMap();return}if(e.target.closest('[data-rt80-toggle-map-rail]')){document.body.classList.toggle('rt80-map-wide');return}},true);
  document.addEventListener('mouseover',e=>showBuildingInspector(e.target,e.clientX,e.clientY),true);document.addEventListener('mousemove',e=>moveInspector(e.clientX,e.clientY),true);document.addEventListener('mouseout',e=>{if(buildingTarget(e.target))hideInspector()},true);
  document.addEventListener('keydown',e=>{const cell=e.target.closest?.('.map-cell.village');if(cell&&(e.key==='Enter'||e.key===' ')){e.preventDefault();cell.click()}},true);
  new MutationObserver(schedule).observe(document.body||document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','style','data-view']});window.addEventListener('resize',schedule,{passive:true});setInterval(schedule,2500);schedule();window.RT80Visual={version:'80.4',refresh:ensure,setVillageCategory,centerMap};
})();
