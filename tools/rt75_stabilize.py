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

# Versão única visível.
h=re.sub(r'<title>Reinos Tribais — RT\d+[^<]*</title>','<title>Reinos Tribais — RT75 Estável</title>',h,count=1)
h=re.sub(r'const VERSION = \d+;','const VERSION = 75;',h,count=1)
h=re.sub(r'const RT_BUILD = "[^"]+";','const RT_BUILD = "75.0";',h,count=1)
h=re.sub(r'\n\s*const RT74_EXECUTION_COMPLETE = true;','',h,count=1)
h=re.sub(r'\n\s*const RT73_FINAL = true;','',h,count=1)
h=re.sub(r'\n\s*const RT72_CONSOLIDATED = true;','',h,count=1)
h=re.sub(r'\n\s*const RT69_FULLFIX = true;','',h,count=1)
anchor='const RT_BUILD = "75.0";'
if anchor not in h: raise SystemExit('RT_BUILD não encontrado')
h=h.replace(anchor,anchor+'\n  const RT75_STABLE = true;',1)
h=h.replace('Reinos Tribais — RT73 • aldeia ativa • sistemas consolidados • mapa vivo • multiplayer','Reinos Tribais — RT75 • aldeia ativa • sistemas consolidados • mapa vivo • multiplayer')
h=h.replace('RT70 GUIADA','RT75 GUIADA').replace('RT70 • interface direta','RT75 • interface consolidada')

# Tabela alfa calculada das artes reais.
alpha_js=json.dumps(alpha,separators=(',',':'),ensure_ascii=False)
root_marker="  const RT60_VILLAGE_LAYER_ROOT = 'assets/v54/buildings';"
if root_marker not in h: raise SystemExit('root marker da aldeia ausente')
# Remove execução anterior se reprocessar.
h=re.sub(r'\n\s*const RT75_SPRITE_ALPHA_BBOX = \{.*?\};\n\s*const RT75_VILLAGE_RENDERER = true;','',h,count=1,flags=re.S)
h=h.replace(root_marker,root_marker+f"\n  const RT75_SPRITE_ALPHA_BBOX = {alpha_js};\n  const RT75_VILLAGE_RENDERER = true;",1)
h=h.replace('  const RT71_VILLAGE_SLOT_RENDERER = true;\n','',1)

start="    const villageLayers=layerEntries.filter(x=>x.visual.tier>0).map(({k,visual})=>{"
pos=h.find(start)
if pos<0: raise SystemExit('renderer antigo villageLayers não encontrado')
end_marker="    }).join('');"
end=h.find(end_marker,pos)
if end<0: raise SystemExit('fim do renderer antigo não encontrado')
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

# CSS autoritativo só para a nova classe; CSS antigo não alcança o renderer RT75.
style=r'''
<style id="rt75-stable-village-css">
.game-shell .village-scene>.rt75-building-art{
  display:block!important;visibility:visible!important;opacity:1!important;position:absolute!important;
  max-width:none!important;max-height:none!important;margin:0!important;padding:0!important;border:0!important;
  object-position:0 0!important;transform:none!important;clip-path:none!important;
  filter:drop-shadow(0 4px 4px rgba(5,7,4,.38))!important;
  image-rendering:auto!important;pointer-events:none!important;
}
.game-shell .village-scene>.rt75-building-wall{filter:drop-shadow(0 3px 3px rgba(5,7,4,.30))!important}
.game-shell .village-scene>.rt75-building-main{filter:drop-shadow(0 5px 5px rgba(5,7,4,.42))!important}
.game-shell .village-scene>.rt60-building-layer{display:none!important}
.game-shell .village-scene>.rt54-map-layer{z-index:1!important}
.game-shell .village-scene>.rt54-interaction-layer,.game-shell .village-scene>.rt24-scene-atmosphere{pointer-events:none!important}
.game-shell .village-scene>.rt60-village-hitbox{z-index:700!important}
</style>
'''
# Idempotência.
h=re.sub(r'\n?<style id="rt75-stable-village-css">.*?</style>\n?','\n',h,count=1,flags=re.S)
h=h.replace('</head>',style+'</head>',1)

# Auditoria estática da build.
checks={
 'version': 'const VERSION = 75;' in h and 'const RT_BUILD = "75.0";' in h and 'RT75_STABLE' in h,
 'legacy_runtime_flags_removed': all(x not in h for x in ['const RT73_FINAL = true;','const RT72_CONSOLIDATED = true;','const RT69_FULLFIX = true;']),
 'new_renderer': 'class="rt75-building-art rt75-building-${k}"' in h,
 'inline_visible': 'display:block!important;visibility:visible!important;opacity:1!important' in h,
 'alpha_table_19': len(alpha)==19 and all(len(v)==4 for v in alpha.values()),
 'old_renderer_class_not_emitted': 'return `<img class="rt60-building-layer rt60-layer-${k}"' not in h,
 'local_save_fix_preserved': 'RT74_LOCAL_AUTOSAVE' in h and 'CLOUD.worldId=null' in h,
 'ranked_rewards_preserved': 'rt74RankedPrizePanel' in h,
 'events_preserved': 'rt74EventsExecutionPanel' in h,
 'monster_exclusive_preserved': 'Monstros e drops exclusivos' in h,
}
if not all(checks.values()):
    raise SystemExit('CHECK FAIL '+json.dumps(checks,ensure_ascii=False))

for p in FILES:p.write_text(h,encoding='utf-8')
report={'build':'RT75','checks':checks,'alpha_bbox':alpha,'sha256':hashlib.sha256(h.encode()).hexdigest()}
Path('AUDITORIA_RT75.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({'build':'RT75','checks':checks,'sha256':report['sha256']},indent=2,ensure_ascii=False))
