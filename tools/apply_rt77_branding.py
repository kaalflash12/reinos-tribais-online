from pathlib import Path
import hashlib

repls={
'<title>Reinos Tribais — RT76 Integrado</title>':'<title>Reinos Tribais — RT77 Funcional</title>',
'RT76 • ONLINE • ADMIN DIRETO + RECOVERY + 19 MENUS':'RT77 • ONLINE • ADMIN DIRETO + RECOVERY + 19 MENUS',
'Realtime + combate RT76 + sincronização':'Realtime + combate RT77 + sincronização',
'<b>RT76 GUIADA</b>':'<b>RT77 GUIADA</b>',
'RT76 • plano integrado':'RT77 • plano funcional',
'REINOS TRIBAIS • CENTRAL OPERACIONAL RT76':'REINOS TRIBAIS • CENTRAL OPERACIONAL RT77',
'interface guiada RT76':'interface guiada RT77',
'RT76 • ALDEIA INTEGRADA • ONLINE':'RT77 • ALDEIA INTEGRADA • ONLINE',
'Reinos Tribais — RT76 • aldeia ativa':'Reinos Tribais — RT77 • aldeia ativa',
'RT76 • aldeia ativa</span>':'RT77 • aldeia ativa</span>',
'Central de Sistemas RT76':'Central de Sistemas RT77',
}
for fn in ('index.html','JOGAR_REINOS_TRIBAIS.html'):
    p=Path(fn); s=p.read_text('utf-8')
    for old,new in repls.items():
        if old in s: s=s.replace(old,new)
    p.write_text(s,'utf-8')
if Path('index.html').read_bytes()!=Path('JOGAR_REINOS_TRIBAIS.html').read_bytes(): raise SystemExit('HTML divergence')
sha=hashlib.sha256(Path('index.html').read_bytes()).hexdigest()
Path('RT77_HTML_SHA256.txt').write_text(sha+'\n',encoding='ascii')
print(sha)
