from pathlib import Path
import re, json, hashlib

HTMLS=[Path('JOGAR_REINOS_TRIBAIS.html'),Path('index.html')]
bridge=Path('tools/rt76_bridge_inside.js').read_text(encoding='utf-8').strip()
wave2=Path('tools/rt76_wave2_inside.js').read_text(encoding='utf-8').strip()
bridge=bridge.replace("const rt76ProcessScheduled=(ts=now())=>{const r=rt76Ensure();let changed=false;","const rt76ProcessScheduled=(ts=now())=>{const r=rt76Ensure();if(!r)return false;let changed=false;")
bridge += "\n  Object.assign(window,{CLOUD,productionPerHour,ensureMarketOffers,hasHeroItem,getVillageVisualStage,sendSupport,travelDuration,aiPersonality,aiPersonalityLabel,storageCapacity});\n" + wave2

VISIBLE_VERSION_REPLACEMENTS={
    'RT70 • ONLINE • ADMIN DIRETO + RECOVERY + 19 MENUS':'RT76 • ONLINE • ADMIN DIRETO + RECOVERY + 19 MENUS',
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

EXPOSE_LINE='Object.assign(window,{CLOUD,productionPerHour,ensureMarketOffers,hasHeroItem,getVillageVisualStage,sendSupport,travelDuration,aiPersonality,aiPersonalityLabel,storageCapacity});'
ANCHOR_LINE="window.addEventListener('beforeunload', () => saveState(true));"

def patch(text):
    text=re.sub(r'/\* RT76_BRIDGE_START \*/.*?/\* RT76_BRIDGE_END \*/\s*','',text,flags=re.S)
    text=re.sub(r'/\* RT76_WAVE2_START \*/.*?/\* RT76_WAVE2_END \*/\s*','',text,flags=re.S)
    text=re.sub(r'^[ \t]*Object\.assign\(window,\{CLOUD,productionPerHour,ensureMarketOffers,hasHeroItem,getVillageVisualStage(?:,sendSupport,travelDuration,aiPersonality,aiPersonalityLabel,storageCapacity)?\}\);[ \t]*$', '', text, flags=re.M)
    text=text.replace('<title>Reinos Tribais — RT75 Estável</title>','<title>Reinos Tribais — RT76 Integrado</title>')
    text=text.replace('const VERSION = 75;','const VERSION = 76;')
    text=text.replace('const RT_BUILD = "75.0";','const RT_BUILD = "76.2";')
    text=text.replace('const RT_BUILD = "76.1";','const RT_BUILD = "76.2";')
    text=text.replace('const RT75_STABLE = true;','const RT76_PLAN = true;')
    text=text.replace('RT75 • versão estável','RT76 • plano integrado')
    for old,new in VISIBLE_VERSION_REPLACEMENTS.items():
        text=text.replace(old,new)
    text=re.sub(r'\s*<script src="rt73-village-runtime\.js\?v=73"></script>','',text)
    text=re.sub(r"\s*if\(managedVillages\.length>1\)\{ RESOURCE_KEYS\.forEach\(resource=>\{.*?\}\); \}\s*",'\n    /* RT76: recursos entre aldeias usam remessas reais do Mercado 2.0; sem teletransporte. */\n',text,flags=re.S)
    anchor_re=r'^[ \t]*'+re.escape(ANCHOR_LINE)+r'[ \t]*$'
    if not re.search(anchor_re,text,flags=re.M): raise RuntimeError('ancora beforeunload nao encontrada')
    text=re.sub(anchor_re,bridge+'\n\n  '+ANCHOR_LINE,text,count=1,flags=re.M)
    runtime='\n<script src="rt76-runtime.js?v=76.2"></script>\n<script src="rt76-map-ai.js?v=76.2"></script>\n<script src="rt76-master-plan.js?v=76.2"></script>\n'
    text=re.sub(r'\s*<script src="rt76-runtime\.js\?v=76\.[12]"></script>\s*','\n',text)
    text=re.sub(r'\s*<script src="rt76-map-ai\.js\?v=76\.[12]"></script>\s*','\n',text)
    text=re.sub(r'\s*<script src="rt76-master-plan\.js\?v=76\.[12]"></script>\s*','\n',text)
    text=text.replace('</body>',runtime+'</body>',1)
    return text

original=HTMLS[0].read_text(encoding='utf-8')
for p in HTMLS:
    p.write_text(patch(p.read_text(encoding='utf-8')),encoding='utf-8')

a=HTMLS[0].read_text(encoding='utf-8'); b=HTMLS[1].read_text(encoding='utf-8')
assert a==b
required=['Reinos Tribais — RT76 Integrado','RT76 • ONLINE • ADMIN DIRETO + RECOVERY + 19 MENUS','const VERSION = 76;','const RT_BUILD = "76.2";','const RT76_PLAN = true;','RT76_BRIDGE_START','window.__RT76_PLAN_APPLIED__=true','RT76_WAVE2_START','window.__RT76_WAVE2_APPLIED__=true','rt76-runtime.js?v=76.2','rt76-map-ai.js?v=76.2','rt76-master-plan.js?v=76.2','sem teletransporte','Central de Sistemas RT76','RT76 • aldeia ativa']
for x in required: assert x in a,x
assert a.count(EXPOSE_LINE)==1, a.count(EXPOSE_LINE)
assert a.count(ANCHOR_LINE)==1, a.count(ANCHOR_LINE)
assert 'rt73-village-runtime.js?v=73' not in a
for forbidden in ['RT70 • ONLINE • ADMIN DIRETO + RECOVERY + 19 MENUS','Central de Sistemas RT69','CENTRAL OPERACIONAL RT75','interface guiada RT75','RT75 GUIADA','RT75 • ALDEIA INTEGRADA • ONLINE','Reinos Tribais — RT75 • aldeia ativa']:
    assert forbidden not in a,forbidden
report={
 'build':'RT76.2','source_html_sha256':hashlib.sha256(original.encode()).hexdigest(),
 'patched_html_sha256':hashlib.sha256(a.encode()).hexdigest(),
 'md_contract':{'file':'Markdown(20260816-185951).md colado','lines':1349,'repo_contract':'PLANO_MESTRE_RT76_CONTRATO.json'},
 'implemented':{
  'phase0_regression_gate':True,'central_war_scheduled_arrival':True,'smart_farm_target_memory':True,
  'incoming_intel_panel':True,'market2_real_trade_equalization':True,'manager2_research_scavenge_log':True,
  'empire_multi_village_view':True,'legacy_rt73_runtime_removed':True,'manager_resource_teleport_removed':True,
  'rt76_test_bridge':True,'scheduler_null_guard':True,'visible_old_version_labels_removed':True,
  'entry_rt76_label':True,'bridge_duplicate_cleanup':True,
  'unified_action_api':True,'map_intelligence_scan_selection':True,'ai_activity_observer':True,'map_ai_ui':True,
  'planner_waves_and_sync':True,'planner_fake':True,'planner_recall':True,'scheduled_support_model':True,
  'farm_configurable_rules':True,'farm_batch_limit':True,'intel_history_and_classification':True,'incoming_progressive_identification':True,
  'market_routes':True,'market_supply_requests':True,'generic_job_queue':True,'ai_job_model':True,
  'governor_profiles':True,'empire_roles_and_bulk_actions':True,'logistics_rules':True,
  'tribe_collective_projects':True,'strategic_alerts':True,'map_context_actions':True,'md_contract_traceability':True
 },
 'not_claimed_complete':['full Supabase transactional P0','entire admin redesign','same-rules local/online proof','all historical requirements']
}
Path('AUDITORIA_RT76_PLANO_APLICADO.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
