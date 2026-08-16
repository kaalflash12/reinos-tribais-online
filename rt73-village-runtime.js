'use strict';

(() => {
  if (window.__RT73_VILLAGE_RUNTIME__) return;
  window.__RT73_VILLAGE_RUNTIME__ = true;

  const SCENE_W = 1671;
  const SCENE_H = 941;
  const BUILDINGS = ['main','timber','clay','iron','farm','warehouse','market','hide','barracks','stable','garage','smith','academy','statue','rally','wall','watchtower','first_church','church'];
  const LABELS = {
    main:'Edifício Principal', timber:'Bosque', clay:'Poço de Argila', iron:'Mina de Ferro', farm:'Fazenda',
    warehouse:'Armazém', market:'Mercado', hide:'Esconderijo', barracks:'Quartel', stable:'Estábulo',
    garage:'Oficina', smith:'Ferreiro', academy:'Academia', statue:'Estátua', rally:'Praça de Reunião',
    wall:'Muralha', watchtower:'Torre de Vigia', first_church:'Primeira Igreja', church:'Igreja'
  };
  const BBOX = {
    church:{0:[717,75,867,198],1:[734,78,850,194],2:[722,55,862,194],3:[712,25,873,194],4:[698,7,885,194]},
    academy:{0:[994,84,1150,213],1:[1025,91,1120,208],2:[1015,63,1128,208],3:[1006,35,1139,208],4:[998,14,1146,208]},
    timber:{0:[405,138,541,250],1:[400,145,544,246],2:[387,122,559,246],3:[404,117,539,248],4:[388,88,558,248]},
    stable:{0:[1241,134,1386,253],1:[1256,141,1372,249],2:[1244,118,1382,249],3:[1231,84,1395,249],4:[1220,68,1405,249]},
    rally:{0:[685,180,830,299],1:[687,186,827,294],2:[676,161,838,294],3:[660,130,854,294],4:[649,115,866,294]},
    farm:{0:[1417,237,1572,364],1:[1414,247,1576,359],2:[1394,219,1596,359],3:[1391,182,1598,360],4:[1376,169,1614,359]},
    main:{0:[890,226,1054,360],1:[916,230,1026,356],2:[908,202,1034,355],3:[896,182,1047,356],4:[890,151,1054,356]},
    barracks:{0:[1151,262,1301,385],1:[1168,268,1285,381],2:[1154,242,1296,381],3:[1142,212,1311,381],4:[1130,194,1322,381]},
    first_church:{0:[311,296,429,393],1:[326,299,414,391],2:[316,281,425,391],3:[306,255,433,391],4:[296,240,443,391]},
    market:{0:[526,279,671,398],1:[536,285,660,393],2:[526,260,670,393],3:[512,236,685,393],4:[500,214,696,393]},
    clay:{0:[221,413,357,525],1:[215,420,363,521],2:[200,397,379,521],3:[218,390,362,523],4:[203,363,376,523]},
    iron:{0:[1050,430,1191,546],1:[1051,442,1189,542],2:[1036,421,1205,542],3:[1021,382,1221,542],4:[1006,368,1236,542]},
    warehouse:{0:[482,450,627,569],1:[503,456,606,565],2:[493,431,615,565],3:[482,400,626,565],4:[472,384,636,565]},
    smith:{0:[691,528,819,633],1:[711,532,798,630],2:[702,510,809,630],3:[692,483,816,630],4:[681,469,829,630]},
    garage:{0:[1304,542,1440,654],1:[1322,546,1422,651],2:[1315,530,1429,650],3:[1304,496,1439,651],4:[1296,481,1448,651]},
    hide:{0:[404,638,530,741],1:[400,645,535,737],2:[380,625,554,737],3:[385,621,549,739],4:[372,595,562,739]},
    wall:{0:[238,671,366,777],1:[244,674,362,773],2:[233,652,371,773],3:[220,626,384,773],4:[218,613,387,773]},
    statue:{0:[769,377,863,454],1:[788,378,845,453],2:[788,361,845,453],3:[786,341,846,453],4:[785,332,847,453]},
    watchtower:{0:[1474,76,1558,145],1:[1501,75,1536,141],2:[1500,62,1539,141],3:[1500,45,1542,141],4:[1488,36,1545,141]}
  };

  const style = document.createElement('style');
  style.id = 'rt73-village-runtime-style';
  style.textContent = `
    .village-scene .rt60-building-layer{display:none!important}
    #rt73-village-overlay{position:absolute;inset:0;z-index:650;pointer-events:none;overflow:hidden}
    #rt73-village-overlay .rt73-building{position:absolute;pointer-events:none;transform:none!important}
    #rt73-village-overlay .rt73-building img{display:block;width:100%;height:100%;object-fit:contain;object-position:center bottom;filter:drop-shadow(0 4px 5px rgba(0,0,0,.40));pointer-events:none}
    #rt73-village-overlay .rt73-hit{position:absolute;z-index:900;border:0;background:transparent;padding:0;pointer-events:auto;cursor:pointer;border-radius:12%}
    #rt73-village-overlay .rt73-hit:hover,#rt73-village-overlay .rt73-hit:focus-visible{outline:2px solid rgba(238,198,88,.78);outline-offset:1px;background:rgba(238,198,88,.035)}
    #rt73-village-overlay .rt73-hit span{position:absolute;left:50%;bottom:0;transform:translate(-50%,115%);white-space:nowrap;background:#10130eee;color:#f2dda0;border:1px solid #8a6a2c;border-radius:5px;padding:4px 7px;font:600 11px system-ui;opacity:0;pointer-events:none}
    #rt73-village-overlay .rt73-hit:hover span,#rt73-village-overlay .rt73-hit:focus-visible span{opacity:1}
    #rt73-village-overlay .rt73-status{position:absolute;left:8px;bottom:8px;z-index:950;padding:4px 7px;border:1px solid #67522a;background:#10140edc;color:#d6bd78;border-radius:5px;font:600 10px system-ui;pointer-events:none}
  `;
  document.head.appendChild(style);

  function scene(){
    return document.querySelector('.village-scene') || document.querySelector('.rt17-village-scene') || document.querySelector('[data-village-scene]');
  }

  function tierFromDom(key){
    const el = document.querySelector(`.rt60-building-layer[data-village-building="${key}"]`);
    if(el){
      const n = Number(el.dataset.villageTier);
      if(Number.isFinite(n)) return Math.max(0,Math.min(4,n));
      const m = (el.getAttribute('src')||'').match(/_l([0-4])\.png/i);
      if(m) return Number(m[1]);
    }
    const hit = document.querySelector(`.rt60-village-hitbox[data-open-building="${key}"],.rt60-village-hitbox[data-village-building="${key}"]`);
    const label = hit?.textContent || hit?.getAttribute('aria-label') || hit?.title || '';
    const m = label.match(/(?:Nv\.?|Nível)\s*([0-9]+)/i);
    return m ? Math.max(0,Math.min(4,Number(m[1]))) : 0;
  }

  function box(key,tier){
    const raw = BBOX[key]?.[tier] || BBOX[key]?.[0];
    if(!raw) return null;
    const [x1,y1,x2,y2] = raw;
    return {
      left:x1/SCENE_W*100,
      top:y1/SCENE_H*100,
      width:(x2-x1)/SCENE_W*100,
      height:(y2-y1)/SCENE_H*100,
      depth:660 + Math.round(y2/SCENE_H*180)
    };
  }

  function openBuilding(key){
    const btn = document.querySelector(`[data-open-building="${key}"]`);
    if(btn){ btn.click(); return; }
    const select = document.querySelector('select[data-building-switch]');
    if(select){
      select.value = key;
      select.dispatchEvent(new Event('change',{bubbles:true}));
      return;
    }
    window.dispatchEvent(new CustomEvent('rt73-open-building',{detail:{key}}));
  }

  function buildOverlay(host){
    if(!host || !host.isConnected) return false;
    host.style.position = 'relative';
    let overlay = host.querySelector('#rt73-village-overlay');
    if(!overlay){
      overlay = document.createElement('div');
      overlay.id = 'rt73-village-overlay';
      host.appendChild(overlay);
    }
    overlay.replaceChildren();

    for(const key of BUILDINGS){
      const tier = tierFromDom(key);
      const b = box(key,tier);
      if(!b) continue;

      const visual = document.createElement('div');
      visual.className = 'rt73-building';
      visual.dataset.key = key;
      Object.assign(visual.style,{left:`${b.left}%`,top:`${b.top}%`,width:`${b.width}%`,height:`${b.height}%`,zIndex:String(b.depth)});

      const img = document.createElement('img');
      img.alt = '';
      img.setAttribute('aria-hidden','true');
      img.draggable = false;
      img.src = `assets/v54/buildings/${key}_l${tier}.png`;
      img.onerror = () => { visual.style.display = 'none'; };
      visual.appendChild(img);
      overlay.appendChild(visual);

      const hit = document.createElement('button');
      hit.type = 'button';
      hit.className = 'rt73-hit';
      hit.title = `${LABELS[key] || key} • Nv.${tier}`;
      hit.setAttribute('aria-label', hit.title);
      Object.assign(hit.style,{left:`${b.left}%`,top:`${b.top}%`,width:`${b.width}%`,height:`${b.height}%`});
      hit.innerHTML = `<span>${LABELS[key] || key} • Nv.${tier}</span>`;
      hit.addEventListener('click',()=>openBuilding(key));
      overlay.appendChild(hit);
    }

    const status = document.createElement('div');
    status.className = 'rt73-status';
    status.textContent = 'RT73 • aldeia ativa';
    overlay.appendChild(status);
    return true;
  }

  let scheduled = false;
  function schedule(){
    if(scheduled) return;
    scheduled = true;
    requestAnimationFrame(()=>{
      scheduled = false;
      const host = scene();
      if(host) buildOverlay(host);
    });
  }

  function boot(){
    schedule();
    const app = document.getElementById('app') || document.body;
    const observer = new MutationObserver(mutations=>{
      if(mutations.every(m=>m.target.closest?.('#rt73-village-overlay'))) return;
      schedule();
    });
    observer.observe(app,{childList:true,subtree:true});
    window.addEventListener('resize',schedule,{passive:true});
    window.addEventListener('load',schedule,{once:true});
    setTimeout(schedule,250);
    setTimeout(schedule,1000);
  }

  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
