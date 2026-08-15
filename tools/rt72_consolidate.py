from pathlib import Path
import re, json, struct, hashlib

PATHS=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]
BUILDINGS=['main','timber','clay','iron','farm','warehouse','market','hide','barracks','stable','garage','smith','academy','statue','rally','wall','watchtower','first_church','church']

for p in PATHS:
    if not p.exists():
        raise SystemExit(f'Arquivo ausente: {p}')

base=PATHS[0].read_text(encoding='utf-8')

ADMIN_PATTERN=re.compile(r'const RT70_ADMIN_DIRECT=true;function rt70FinalizeModal\(id\)\{.*?setTimeout\(rt70StampAdmin,0\);',re.S)
ADMIN_REPLACEMENT=r'''const RT70_ADMIN_DIRECT=true,RT72_ADMIN_DIRECT=true;
function rt70FinalizeModal(id){
  const modal=document.getElementById(id);if(!modal)return;
  modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');
  const title=modal.querySelector('h2');if(title){if(!title.id)title.id=id+'-title';modal.setAttribute('aria-labelledby',title.id)}
  const body=modal.querySelector('.rt70-modal-body')||modal;
  const raw=[...body.querySelectorAll('textarea.jsonarea')];raw.forEach(ta=>ta.hidden=true);
  body.querySelectorAll('textarea.jsonarea').forEach(ta=>{try{rt66EnhanceJsonArea(ta)}catch(e){console.error('RT72 enhancer',ta.name,e)}});
  try{rt66EnhanceEntitlementForm()}catch(e){}
  try{rt67UpdateRewardForm()}catch(e){}
  try{rt66EnhancePlayerTabs()}catch(e){}
  try{rt66EnhanceVillageTabs()}catch(e){}
  try{rt66EnhanceTechnicalCodes()}catch(e){}
  try{rt66HumanizeEnums()}catch(e){}
  raw.forEach(ta=>{if(ta.closest('.rt66-advanced'))ta.hidden=false});
  const form=body.querySelector('form');
  if(form&&!form.querySelector('.rt70-admin-status'))form.insertAdjacentHTML('afterbegin','<div class="rt70-admin-status"><span>●</span><b>RT72 GUIADA</b> tarefas comuns usam controles visuais; dados técnicos ficam somente em Avançado.</div>');
}
function rt70StampAdmin(){const intro=document.querySelector('.rt67-page-intro');if(intro&&!intro.querySelector('.rt70-build-badge'))intro.insertAdjacentHTML('beforeend','<span class="rt70-build-badge">RT72 • revisão consolidada</span>')}
const RT70_OBSERVER=new MutationObserver(()=>queueMicrotask(rt70StampAdmin));RT70_OBSERVER.observe(document.documentElement,{childList:true,subtree:true});window.addEventListener('DOMContentLoaded',rt70StampAdmin);setTimeout(rt70StampAdmin,0);
if(!window.RT72_MODAL_EVENTS_BOUND){window.RT72_MODAL_EVENTS_BOUND=true;document.addEventListener('keydown',e=>{if(e.key==='Escape'){const m=[...document.querySelectorAll('.rt64-modal')].pop();if(m)rt64CloseModal(m.id)}});document.addEventListener('click',e=>{if(e.target?.classList?.contains('rt64-modal'))rt64CloseModal(e.target.id)})}'''

CSS=r'''
<style id="rt72-consolidated-css">
/* RT72 — última camada: aldeia, edifícios, menus e administração */
.game-shell .village-scene{position:relative!important;overflow:hidden!important;isolation:isolate!important;aspect-ratio:1671/941!important;height:auto!important;min-height:0!important;max-height:none!important;background:#1a2317!important}
.game-shell .village-scene>.rt54-map-layer{position:absolute!important;inset:0!important;width:100%!important;height:100%!important;object-fit:fill!important;z-index:1!important}
.game-shell .rt60-building-layer{position:absolute!important;inset:auto!important;object-fit:contain!important;object-position:center bottom!important;pointer-events:none!important;transform:none!important;max-width:none!important;max-height:none!important;filter:drop-shadow(0 3px 3px rgba(5,7,4,.34))!important}
.game-shell .rt60-village-hitbox{z-index:700!important;background:transparent!important}
.game-shell .rt54-interaction-layer,.game-shell .rt24-scene-atmosphere{pointer-events:none!important}
.game-shell .rt64-building-groups{display:grid!important;grid-template-columns:repeat(auto-fit,minmax(138px,1fr))!important;gap:5px!important;overflow:visible!important;padding:6px 0!important}
.game-shell .rt64-building-groups button{min-width:0!important;width:100%!important;justify-content:flex-start!important;overflow:hidden!important}
.game-shell .rt64-building-groups button b{overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
.game-shell .rt64-building-quicknav{position:sticky!important;top:92px!important;z-index:40!important;background:#0d100cf5!important;padding:6px!important;border:1px solid #4f4328!important}
.game-shell .rt64-building-actionbar{position:sticky!important;top:178px!important;z-index:39!important}
.rt64-modal{overflow:hidden!important;padding:12px!important}.rt64-modal>section{width:min(1260px,calc(100vw - 24px))!important;height:min(92vh,900px)!important;max-height:92vh!important;overflow:hidden!important;display:grid!important;grid-template-rows:auto minmax(0,1fr)!important;padding:0!important}.rt64-modal>section>header{position:relative!important;top:auto!important;margin:0!important;padding:13px 15px!important}.rt70-modal-body{min-height:0!important;overflow:auto!important;padding:14px 16px 20px!important}.rt64-modal textarea.jsonarea[hidden]{display:none!important}.rt66-section-tabs{top:0!important;z-index:12!important}.rt66-pane{min-width:0!important}.rt66-advanced{margin-top:12px!important}.rt66-advanced:not([open]) textarea{display:none!important}.rt70-admin-status{position:relative!important;margin-bottom:10px!important}.rt67-step-card{min-width:0!important}.rt67-reward-steps select,.rt67-reward-steps input{max-width:100%!important}
@media(max-width:900px){.game-shell .rt64-building-groups{display:flex!important;overflow-x:auto!important}.game-shell .rt64-building-groups button{flex:0 0 150px!important}.game-shell .rt64-building-actionbar{top:150px!important}.rt64-modal{padding:4px!important}.rt64-modal>section{width:calc(100vw - 8px)!important;height:calc(100vh - 8px)!important;max-height:calc(100vh - 8px)!important}.rt70-modal-body{padding:9px!important}.rt66-section-tabs{overflow-x:auto!important;flex-wrap:nowrap!important}.rt66-section-tabs button{flex:0 0 auto!important}}
</style>
'''

GUARD=r'''
<script id="rt72-runtime-guard">
(()=>{window.RT72_VISUAL_GUARD=true;document.addEventListener('error',e=>{const el=e.target;if(el?.tagName==='IMG'&&el.closest?.('.village-scene')){el.style.display='none';console.error('RT72 asset de aldeia ausente:',el.src)}},true)})();
</script>
'''

def patch(t:str)->str:
    t=re.sub(r'<title>Reinos Tribais — RT\d+[^<]*</title>','<title>Reinos Tribais — RT72 Consolidada</title>',t,count=1)
    t=re.sub(r'  const VERSION = \d+;','  const VERSION = 72;',t,count=1)
    t=re.sub(r'  const RT_BUILD = "[^"]+";','  const RT_BUILD = "72.0";',t,count=1)
    if 'const RT72_CONSOLIDATED = true;' not in t:
        anchor='  const RT_BUILD = "72.0";'
        if anchor not in t: raise SystemExit('RT_BUILD não localizado')
        t=t.replace(anchor,anchor+'\n  const RT72_CONSOLIDATED = true;',1)

    replacements={
      'REINOS TRIBAIS • CENTRAL OPERACIONAL RT70 DIRETA':'REINOS TRIBAIS • CENTRAL OPERACIONAL RT72',
      'interface guiada RT69':'interface guiada RT72',
      'RT69 • ALDEIA INTEGRADA • ONLINE':'RT72 • ALDEIA INTEGRADA • ONLINE',
      'Reinos Tribais — RT69 • aldeia corrigida • sistemas auditados • mapa vivo • multiplayer':'Reinos Tribais — RT72 • aldeia integrada • sistemas consolidados • mapa vivo • multiplayer',
      'Modo guiado RT66 ativo':'Modo guiado ativo',
      'RT71 GUIADA':'RT72 GUIADA',
      'RT71 • aldeia corrigida':'RT72 • revisão consolidada',
    }
    for a,b in replacements.items(): t=t.replace(a,b)

    if 'RT72_ADMIN_DIRECT=true' not in t:
        if not ADMIN_PATTERN.search(t): raise SystemExit('rt70FinalizeModal não localizado')
        t=ADMIN_PATTERN.sub(lambda m:ADMIN_REPLACEMENT,t,count=1)

    if 'RT71_VILLAGE_SLOT_RENDERER' not in t: raise SystemExit('RT71 village renderer ausente')
    if 'RT60_VILLAGE_BBOX[k]?.[tier]' not in t: raise SystemExit('BBOX renderer ausente')
    if 'left:${left}%;top:${top}%;width:${width}%;height:${height}%' not in t: raise SystemExit('dimensões por lote ausentes')

    if 'id="rt72-consolidated-css"' not in t:
        if '</head>' not in t: raise SystemExit('</head> ausente')
        t=t.replace('</head>',CSS+'</head>',1)
    if 'id="rt72-runtime-guard"' not in t:
        if '</body>' not in t: raise SystemExit('</body> ausente')
        t=t.replace('</body>',GUARD+'</body>',1)
    return t

fixed=patch(base)
for p in PATHS: p.write_text(fixed,encoding='utf-8')

checks={}
checks['html_identical']=PATHS[0].read_bytes()==PATHS[1].read_bytes()
checks['version_72']='const VERSION = 72;' in fixed and 'const RT_BUILD = "72.0";' in fixed
checks['consolidated_marker']='RT72_CONSOLIDATED' in fixed
checks['village_bbox_renderer']='RT60_VILLAGE_BBOX[k]?.[tier]' in fixed and 'data-village-building' in fixed
checks['no_fullscreen_building_rule']='rt60-building-layer{position:absolute!important;inset:0!important;width:100%!important;height:100%!important;object-fit:fill' not in fixed
checks['building_quicknav']='data-building-switch' in fixed and 'rt64-building-groups' in fixed
checks['admin_guided']='RT72_ADMIN_DIRECT' in fixed and 'RT72 GUIADA' in fixed and 'rt67RewardFormHtml' in fixed
checks['raw_json_hidden_first']='raw.forEach(ta=>ta.hidden=true)' in fixed
checks['modal_escape']='RT72_MODAL_EVENTS_BOUND' in fixed
checks['responsive_css']='id="rt72-consolidated-css"' in fixed
checks['runtime_asset_guard']='RT72_VISUAL_GUARD' in fixed
checks['19_action_configs']=all(re.search(rf'\b{re.escape(k)}\s*:\s*\[',fixed) for k in BUILDINGS)
checks['19_bbox_configs']=all(re.search(rf'"{re.escape(k)}"\s*:\s*\{{"0"',fixed) for k in BUILDINGS)

missing=[];dims={}
for b in BUILDINGS:
    for level in range(5):
        p=Path(f'assets/v54/buildings/{b}_l{level}.png')
        if not p.exists():
            missing.append(str(p));continue
        data=p.read_bytes()
        if len(data)>=24 and data[:8]==b'\x89PNG\r\n\x1a\n':
            dims[f'{b}_l{level}']=list(struct.unpack('>II',data[16:24]))
checks['95_building_assets']=not missing
checks['4_village_maps']=all(Path(f'assets/v54/map/village_stage{i}.png').exists() for i in range(1,5))

forbidden=['CENTRAL OPERACIONAL RT70 DIRETA','interface guiada RT69','RT69 • ALDEIA INTEGRADA • ONLINE','Modo guiado RT66 ativo','RT71 GUIADA','RT71 • aldeia corrigida']
leftovers=[x for x in forbidden if x in fixed]
checks['no_stale_visible_versions']=not leftovers

report={
  'version':'RT72','build':'72.0','checks':checks,
  'assets':{'building_files':95-len(missing),'expected':95,'missing':missing,'dimensions':dims},
  'visible_version_leftovers':leftovers,
  'sha256':hashlib.sha256(fixed.encode()).hexdigest()
}
Path('AUDITORIA_RT72_CONSOLIDADA.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(checks,ensure_ascii=False,indent=2))
if not all(checks.values()): raise SystemExit('AUDITORIA RT72 FALHOU')
print('RT72 STRUCTURAL PASS')
