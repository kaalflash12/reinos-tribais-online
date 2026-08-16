from pathlib import Path
from PIL import Image
import json,re,hashlib

FILES=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]
if not all(p.exists() for p in FILES): raise SystemExit('HTML principal ausente')
a=FILES[0].read_text(encoding='utf-8'); b=FILES[1].read_text(encoding='utf-8')
if a!=b: raise SystemExit('index e JOGAR divergentes antes da RT75')
h=a

KEYS=['main','timber','clay','iron','farm','warehouse','market','hide','barracks','stable','garage','smith','academy','statue','rally','wall','watchtower','first_church','church']
root=Path('assets/v54/buildings')
alpha={}
for k in KEYS:
    alpha[k]={}
    for lvl in range(1,5):
        p=root/f'{k}_l{lvl}.png'
        if not p.exists(): raise SystemExit(f'asset ausente: {p}')
        im=Image.open(p).convert('RGBA')
        if im.size!=(480,400): raise SystemExit(f'dimensão inválida: {p} {im.size}')
        box=im.getchannel('A').getbbox()
        if not box: raise SystemExit(f'arte construída transparente: {p}')
        alpha[k][str(lvl)]=list(box)

h=re.sub(r'<title>Reinos Tribais — RT\d+[^<]*</title>','<title>Reinos Tribais — RT75 Estável</title>',h,count=1)
h=re.sub(r'const VERSION = \d+;','const VERSION = 75;',h,count=1)
h=re.sub(r'const RT_BUILD = "[^"]+";','const RT_BUILD = "75.0";',h,count=1)
for name in ['RT75_STABLE','RT74_EXECUTION_COMPLETE','RT73_FINAL','RT72_CONSOLIDATED','RT69_FULLFIX']:
    h=re.sub(r'\n\s*const '+re.escape(name)+r' = true;','',h,count=1)
anchor='const RT_BUILD = "75.0";'
if anchor not in h: raise SystemExit('RT_BUILD não encontrado')
h=h.replace(anchor,anchor+'\n  const RT75_STABLE = true;',1)
replacements={
 'Reinos Tribais — RT73 • aldeia ativa • sistemas consolidados • mapa vivo • multiplayer':'Reinos Tribais — RT75 • aldeia ativa • sistemas consolidados • mapa vivo • multiplayer',
 'RT73 • ALDEIA INTEGRADA • ONLINE':'RT75 • ALDEIA INTEGRADA • ONLINE',
 'RT73 GUIADA':'RT75 GUIADA','RT73 • versão final':'RT75 • versão estável',
 'CENTRAL OPERACIONAL RT73':'CENTRAL OPERACIONAL RT75','interface guiada RT73':'interface guiada RT75',
 'RT70 GUIADA':'RT75 GUIADA','RT70 • interface direta':'RT75 • interface consolidada'
}
for old,new in replacements.items(): h=h.replace(old,new)

alpha_js=json.dumps(alpha,separators=(',',':'),ensure_ascii=False)
root_marker="  const RT60_VILLAGE_LAYER_ROOT = 'assets/v54/buildings';"
if root_marker not in h: raise SystemExit('root marker da aldeia ausente')
h=re.sub(r'\n\s*const RT75_SPRITE_ALPHA_BBOX = \{.*?\};\n\s*const RT75_VILLAGE_RENDERER = true;','',h,count=1,flags=re.S)
h=h.replace(root_marker,root_marker+f"\n  const RT75_SPRITE_ALPHA_BBOX = {alpha_js};\n  const RT75_VILLAGE_RENDERER = true;",1)
h=h.replace('  const RT71_VILLAGE_SLOT_RENDERER = true;\n','',1)

start="    const villageLayers=layerEntries.filter(x=>x.visual.tier>0).map(({k,visual})=>{"
pos=h.find(start)
if pos<0: raise SystemExit('renderer villageLayers não encontrado')
end_marker="    }).join('');"; end=h.find(end_marker,pos)
if end<0: raise SystemExit('fim do renderer não encontrado')
end+=len(end_marker)
new_renderer=r'''    const villageLayers=layerEntries.filter(x=>x.visual.tier>0).map(({k,visual})=>{
      const tier=String(visual.tier||1);
      const target=RT60_VILLAGE_BBOX[k]?.[tier]||RT60_VILLAGE_BBOX[k]?.['1'];
      const alpha=RT75_SPRITE_ALPHA_BBOX[k]?.[tier];
      if(!target||!alpha)return '';
      const [x1,y1,x2,y2]=target,[ax1,ay1,ax2,ay2]=alpha;
      const scaleX=(x2-x1)/Math.max(1,ax2-ax1),scaleY=(y2-y1)/Math.max(1,ay2-ay1);
      const fullLeft=x1-ax1*scaleX,fullTop=y1-ay1*scaleY,fullWidth=480*scaleX,fullHeight=400*scaleY;
      const left=fullLeft/RT60_VILLAGE_SCENE_SIZE.width*100,top=fullTop/RT60_VILLAGE_SCENE_SIZE.height*100;
      const width=fullWidth/RT60_VILLAGE_SCENE_SIZE.width*100,height=fullHeight/RT60_VILLAGE_SCENE_SIZE.height*100;
      const depth=20+Math.round(y2/RT60_VILLAGE_SCENE_SIZE.height*300);
      return `<img class="rt75-building-art rt75-building-${k}" data-village-building="${k}" data-village-tier="${tier}" data-alpha-bbox="${alpha.join(',')}" data-target-bbox="${target.join(',')}" src="${RT60_VILLAGE_LAYER_ROOT}/${k}_l${visual.tier}.png" alt="${escapeHtml(D.buildings[k]?.name||k)}" style="display:block!important;visibility:visible!important;opacity:1!important;position:absolute!important;left:${left}%;top:${top}%;width:${width}%;height:${height}%;object-fit:fill!important;z-index:${depth}!important;pointer-events:none!important" draggable="false">`;
    }).join('');'''
h=h[:pos]+new_renderer+h[end:]

scene_tail='${villageLayers}${hotspotMarkup}</div>'
scene_tail_new='${villageLayers}${hotspotMarkup}<span class="rt75-scene-build" aria-hidden="true">RT75 • aldeia ativa</span></div>'
h=h.replace(scene_tail_new,scene_tail,1)
if scene_tail not in h: raise SystemExit('fechamento da cena não encontrado')
h=h.replace(scene_tail,scene_tail_new,1)

style=r'''
<style id="rt75-stable-village-css">
/* RT75 é o único renderer visual/clicável autorizado da aldeia. */
.game-shell #rt73-village-overlay,.game-shell #rt73-village-overlay *,.game-shell .rt73-building,.game-shell .rt73-hit,.game-shell .rt73-status{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important}
.game-shell .village-scene>.rt75-building-art{display:block!important;visibility:visible!important;opacity:1!important;position:absolute!important;max-width:none!important;max-height:none!important;margin:0!important;padding:0!important;border:0!important;object-position:0 0!important;transform:none!important;clip-path:none!important;filter:drop-shadow(0 4px 4px rgba(5,7,4,.38))!important;image-rendering:auto!important;pointer-events:none!important}
.game-shell .village-scene>.rt75-building-wall{filter:drop-shadow(0 3px 3px rgba(5,7,4,.30))!important}
.game-shell .village-scene>.rt75-building-main{filter:drop-shadow(0 5px 5px rgba(5,7,4,.42))!important}
.game-shell .village-scene>.rt60-building-layer{display:none!important}
.game-shell .village-scene>.rt54-map-layer{z-index:1!important}
.game-shell .village-scene>.rt54-interaction-layer,.game-shell .village-scene>.rt24-scene-atmosphere{pointer-events:none!important}
.game-shell .village-scene>.rt60-village-hitbox{z-index:700!important}
.game-shell .village-scene>.rt75-scene-build{position:absolute!important;left:7px!important;bottom:6px!important;z-index:850!important;display:block!important;padding:3px 7px!important;border:1px solid #96752f!important;border-radius:3px!important;background:#11160ff2!important;color:#efd174!important;font:800 10px/1.2 Arial,sans-serif!important;letter-spacing:.02em!important;box-shadow:0 2px 5px #0008!important;pointer-events:none!important}
@media(max-width:760px){.game-shell .rt22-center{overflow-x:hidden!important;max-width:100%!important}.game-shell .rt22-center .village-scene,.game-shell .rt22-center .rt17-village-scene{width:100%!important;max-width:100%!important;height:auto!important;min-height:0!important;aspect-ratio:1671/941!important;overflow:hidden!important}.game-shell .village-scene>.rt75-scene-build{left:4px!important;bottom:4px!important;font-size:7px!important;padding:2px 4px!important}}
</style>
'''
h=re.sub(r'\n?<style id="rt75-stable-village-css">.*?</style>\n?','\n',h,count=1,flags=re.S)
h=h.replace('</head>',style+'</head>',1)

checks={
 'version':'const VERSION = 75;' in h and 'const RT_BUILD = "75.0";' in h and h.count('const RT75_STABLE = true;')==1,
 'legacy_runtime_flags_removed':all(x not in h for x in ['const RT73_FINAL = true;','const RT72_CONSOLIDATED = true;','const RT69_FULLFIX = true;']),
 'new_renderer':'class="rt75-building-art rt75-building-${k}"' in h,
 'alpha_table_19':len(alpha)==19 and all(len(v)==4 for v in alpha.values()),
 'legacy_rt73_overlay_disabled':'#rt73-village-overlay' in style and '.rt73-hit' in style and 'pointer-events:none!important' in style,
 'mobile_fit':'@media(max-width:760px)' in style and 'width:100%!important;max-width:100%!important' in style,
 'scene_version_badge':'class="rt75-scene-build"' in h,
 'visible_rt73_labels_removed':all(x not in h for x in ['RT73 • ALDEIA INTEGRADA • ONLINE','RT73 GUIADA','RT73 • versão final','CENTRAL OPERACIONAL RT73','interface guiada RT73','Reinos Tribais — RT73 • aldeia ativa']),
 'local_save_fix_preserved':'RT74_LOCAL_AUTOSAVE' in h and 'CLOUD.worldId=null' in h,
 'ranked_rewards_preserved':'rt74RankedPrizePanel' in h,
 'events_preserved':'rt74EventsExecutionPanel' in h,
 'monster_exclusive_preserved':'Monstros e drops exclusivos' in h,
}
if not all(checks.values()): raise SystemExit('CHECK FAIL '+json.dumps(checks,ensure_ascii=False))
for p in FILES:p.write_text(h,encoding='utf-8')
report={'build':'RT75','checks':checks,'alpha_bbox':alpha,'sha256':hashlib.sha256(h.encode()).hexdigest()}
Path('AUDITORIA_RT75.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({'build':'RT75','checks':checks,'sha256':report['sha256']},indent=2,ensure_ascii=False))
