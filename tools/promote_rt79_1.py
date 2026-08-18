from pathlib import Path

FILES=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]
for path in FILES:
    text=path.read_text(encoding='utf-8')
    text=text.replace('<title>Reinos Tribais — RT78 Estratégia Completa</title>','<title>Reinos Tribais — RT79.1 Revisado</title>')
    text=text.replace('const VERSION = 78;','const VERSION = 79;')
    text=text.replace('const RT_BUILD = "78.0";','const RT_BUILD = "79.1";')
    text=text.replace("window.RT76={version:'78.0'","window.RT76={version:'79.1'")
    text=text.replace("window.RT79_CORE = {version:'79.0'","window.RT79_CORE = {version:'79.1'")
    text=text.replace('Realtime + combate RT77 + sincronização','Realtime + combate RT79.1 + sincronização')
    text=text.replace('RT77 GUIADA','RT79.1 GUIADA').replace('RT77 • plano funcional','RT79.1 • plano funcional')
    text=text.replace('CENTRAL OPERACIONAL RT77','CENTRAL OPERACIONAL RT79.1').replace('interface guiada RT77','interface guiada RT79.1')
    text=text.replace('RT77 • ALDEIA INTEGRADA • ONLINE','RT79.1 • ALDEIA INTEGRADA • ONLINE')
    text=text.replace('RT77 • aldeia ativa','RT79.1 • aldeia ativa')
    text=text.replace('Central de Sistemas RT77','Central de Sistemas RT79.1')
    text=text.replace('RT62 com os 19 edifícios ancorados pelos lotes','RT79.1 com os 19 edifícios ancorados pelos lotes')
    text=text.replace('[76,77,78].includes','[76,77,78,79].includes')
    marker='</body>'
    loaders='''
<script src="rt79-suite.js?v=79.1"></script>
<script src="rt79-groups-addon.js?v=79.1"></script>
<script src="rt79-logistics-ai-addon.js?v=79.1"></script>
<script src="rt79-village-ui.js?v=79.1"></script>
<script src="rt79-admin-suite.js?v=79.1"></script>
<script src="rt79-admin-logistics-addon.js?v=79.1"></script>
'''
    if 'rt79-suite.js' not in text:
        text=text.replace(marker,loaders+marker)
    else:
        text=text.replace('?v=79.0','?v=79.1')
    path.write_text(text,encoding='utf-8')
FILES[1].write_bytes(FILES[0].read_bytes())

html=FILES[0].read_text(encoding='utf-8')
required=[
    'const VERSION = 79;',
    'const RT_BUILD = "79.1";',
    'rt79-suite.js?v=79.1',
    'rt79-groups-addon.js?v=79.1',
    'rt79-logistics-ai-addon.js?v=79.1',
    'rt79-village-ui.js?v=79.1',
    'rt79-admin-suite.js?v=79.1',
    'rt79-admin-logistics-addon.js?v=79.1',
]
missing=[x for x in required if x not in html]
if missing:
    raise SystemExit('RT79.1 promotion incomplete: '+', '.join(missing))
if FILES[0].read_bytes()!=FILES[1].read_bytes():
    raise SystemExit('index.html and JOGAR_REINOS_TRIBAIS.html diverged')
print('RT79.1 physical promotion PASS')
