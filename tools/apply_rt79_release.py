from pathlib import Path

FILES=['index.html','JOGAR_REINOS_TRIBAIS.html']
LOADERS=[
    '<script src="rt79-suite.js?v=79.0"></script>',
    '<script src="rt79-groups-addon.js?v=79.0"></script>',
    '<script src="rt79-logistics-ai-addon.js?v=79.0"></script>',
    '<script src="rt79-village-ui.js?v=79.0"></script>',
    '<script src="rt79-admin-suite.js?v=79.0"></script>',
]
for name in FILES:
    p=Path(name)
    s=p.read_text(encoding='utf-8')
    s=s.replace('<title>Reinos Tribais — RT78 Estratégia Completa</title>','<title>Reinos Tribais — RT79 Completo</title>')
    s=s.replace('const VERSION = 78;','const VERSION = 79;')
    s=s.replace('const RT_BUILD = "78.0";','const RT_BUILD = "79.0";')
    s=s.replace('RT78 • ONLINE • ESTRATÉGIA + ADMIN + RECOVERY','RT79 • ONLINE • ESTRATÉGIA + ADMIN + RECOVERY')
    s=s.replace('Reinos Tribais — RT78 • estratégia server-side','Reinos Tribais — RT79 • estratégia server-side')
    s=s.replace('[17,18,19,20,21,22,23,24,25,49,50,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78].includes','[17,18,19,20,21,22,23,24,25,49,50,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79].includes')
    if 'window.CLOUD=CLOUD;' not in s:
        s=s.replace("window.RT76={version:'77.0'", "window.CLOUD=CLOUD;\n  window.RT76={version:'79.0'")
    else:
        s=s.replace("window.RT76={version:'77.0'", "window.RT76={version:'79.0'").replace("window.RT76={version:'78.0'", "window.RT76={version:'79.0'")
    if 'window.RT79_CORE' not in s:
        s=s.replace('  window.RT77 = window.RT76;','  window.RT77 = window.RT76;\n  window.RT79_CORE = {version:\'79.0\',cloud:()=>CLOUD,state:()=>state,render:()=>renderAll(),save:()=>saveState(true)};')
    anchor='<script src="rt76-master-plan.js?v=78.0"></script>'
    if anchor not in s:
        raise RuntimeError(f'loader anchor missing: {name}')
    for tag in LOADERS:
        if tag not in s:
            s=s.replace(anchor,anchor+'\n'+tag)
    required=['const VERSION = 79;','const RT_BUILD = "79.0";','window.CLOUD=CLOUD;','rt79-suite.js?v=79.0','rt79-groups-addon.js?v=79.0','rt79-logistics-ai-addon.js?v=79.0','rt79-village-ui.js?v=79.0','rt79-admin-suite.js?v=79.0']
    missing=[x for x in required if x not in s]
    if missing:
        raise RuntimeError(f'RT79 markers missing after patch in {name}: {missing}')
    p.write_text(s,encoding='utf-8')
print('RT79 complete release patch applied')
