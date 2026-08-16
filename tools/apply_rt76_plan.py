from pathlib import Path
import re, json, hashlib

HTMLS=[Path('JOGAR_REINOS_TRIBAIS.html'),Path('index.html')]
bridge=Path('tools/rt76_bridge_inside.js').read_text(encoding='utf-8').strip()
wave2=Path('tools/rt76_wave2_inside.js').read_text(encoding='utf-8').strip()
bridge=bridge.replace("const rt76ProcessScheduled=(ts=now())=>{const r=rt76Ensure();let changed=false;","const rt76ProcessScheduled=(ts=now())=>{const r=rt76Ensure();if(!r)return false;let changed=false;")
bridge += "\n  Object.assign(window,{CLOUD,productionPerHour,ensureMarketOffers,hasHeroItem,getVillageVisualStage});\n" + wave2

VISIBLE_VERSION_REPLACEMENTS={
    'Central de Sistemas RT69':'Central de Sistemas RT76',
    'combate RT69':'combate RT76',
    'Suspenso pelo painel administrativo RT69':'Suspenso pelo painel administrativo RT76',
    'RT75 GUIADA':'RT76 GUIADA',
    'CENTRAL OPERACIONAL RT75':'CENTRAL OPERACIONAL RT76',
    'interface guiada RT75':'interface guiada RT76',
    'RT75 • ALDEIA INTEGRADA • ONLINE':'RT76 • ALDEIA INTEGRADA • ONLINE',
    'Reinos Tribais — RT75 • aldeia ativa • sistemas consolidados • mapa vivo • multiplayer':'Reinos Tribais — RT76 • aldeia ativa • sistemas consolidados • mapa vivo • multiplayer',
    'RT75 • aldeia ativa':'RT76 • aldeia ativa',
}

def patch(text):
    text=re.sub(r'/\* RT76_BRIDGE_START \*/.*?/\* RT76_BRIDGE_END \*/\s*','',text,flags=re.S)
    text=re.sub(r'/\* RT76_WAVE2_START \*/.*?/\* RT76_WAVE2_END \*/\s*','',text,flags=re.S)
    text=text.replace('<title>Reinos Tribais — RT75 Estável</title>','<title>Reinos Tribais — RT76 Integrado</title>')
    text=text.replace('const VERSION = 75;','const VERSION = 76;')
    text=text.replace('const RT_BUILD = "75.0";','const RT_BUILD = "76.1";')
    text=text.replace('const RT75_STABLE = true;','const RT76_PLAN = true;')
    text=text.replace('RT75 • versão estável','RT76 • plano integrado')
    for old,new in VISIBLE_VERSION_REPLACEMENTS.items():
        text=text.replace(old,new)
    text=re.sub(r'\s*<script src="rt73-village-runtime\.js\?v=73"></script>','',text)
    text=re.sub(r"\s*if\(managedVillages\.length>1\)\{ RESOURCE_KEYS\.forEach\(resource=>\{.*?\}\); \}\s*",'\n    /* RT76: recursos entre aldeias usam remessas reais do Mercado 2.0; sem teletransporte. */\n',text,flags=re.S)
    anchor="  window.addEventListener('beforeunload', () => saveState(true));"
    if anchor not in text: raise RuntimeError('âncora beforeunload não encontrada')
    text=text.replace(anchor,bridge+'\n\n'+anchor,1)
    runtime='\n<script src="rt76-runtime.js?v=76.1"></script>\n'
    if 'rt76-runtime.js?v=76.1' not in text:
        text=text.replace('</body>',runtime+'</body>',1)
    return text

original=HTMLS[0].read_text(encoding='utf-8')
for p in HTMLS:
    p.write_text(patch(p.read_text(encoding='utf-8')),encoding='utf-8')

a=HTMLS[0].read_text(encoding='utf-8'); b=HTMLS[1].read_text(encoding='utf-8')
assert a==b
required=['Reinos Tribais — RT76 Integrado','const VERSION = 76;','const RT_BUILD = "76.1";','const RT76_PLAN = true;','RT76_BRIDGE_START','window.__RT76_PLAN_APPLIED__=true','RT76_WAVE2_START','window.__RT76_WAVE2_APPLIED__=true','rt76-runtime.js?v=76.1','sem teletransporte','Central de Sistemas RT76','RT76 • aldeia ativa']
for x in required: assert x in a,x
assert 'rt73-village-runtime.js?v=73' not in a
for forbidden in ['Central de Sistemas RT69','CENTRAL OPERACIONAL RT75','interface guiada RT75','RT75 GUIADA','RT75 • ALDEIA INTEGRADA • ONLINE','Reinos Tribais — RT75 • aldeia ativa']:
    assert forbidden not in a,forbidden
report={
 'build':'RT76.1','source_html_sha256':hashlib.sha256(original.encode()).hexdigest(),
 'patched_html_sha256':hashlib.sha256(a.encode()).hexdigest(),
 'implemented':{
  'phase0_regression_gate':True,'central_war_scheduled_arrival':True,'smart_farm_target_memory':True,
  'incoming_intel_panel':True,'market2_real_trade_equalization':True,'manager2_research_scavenge_log':True,
  'empire_multi_village_view':True,'legacy_rt73_runtime_removed':True,'manager_resource_teleport_removed':True,
  'rt76_test_bridge':True,'scheduler_null_guard':True,'visible_old_version_labels_removed':True,
  'unified_action_api':True,'map_intelligence_scan_selection':True,'ai_activity_observer':True
 },
 'not_claimed_complete':['full Supabase transactional P0','entire admin redesign','all 15 master-plan phases','all historical requirements']
}
Path('AUDITORIA_RT76_PLANO_APLICADO.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
