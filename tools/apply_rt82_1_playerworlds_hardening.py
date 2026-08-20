from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
HTMLS=[ROOT/'index.html',ROOT/'JOGAR_REINOS_TRIBAIS.html']
FORBIDDEN=('crowns','flags_inventory','premium')

for path in HTMLS:
    src=path.read_text(encoding='utf-8')
    m=re.search(r"  async function upsertPlayerSummary\(\) \{.*?\n  \}\n",src,re.S)
    if not m:
        raise SystemExit(f'{path.name}: upsertPlayerSummary não encontrado')
    block=m.group(0)
    original=block
    for key in FORBIDDEN:
        block=re.sub(rf"^\s{{6}}{re.escape(key)}:\s*.*?\n",'',block,count=1,flags=re.M)
    if block==original:
        # Idempotência: só aceita se os campos já estiverem ausentes.
        if any(re.search(rf"^\s*{re.escape(key)}\s*:",block,re.M) for key in FORBIDDEN):
            raise SystemExit(f'{path.name}: campos competitivos não removidos')
    for key in FORBIDDEN:
        if re.search(rf"^\s*{re.escape(key)}\s*:",block,re.M):
            raise SystemExit(f'{path.name}: {key} ainda está no resumo REST')
    src=src[:m.start()]+block+src[m.end():]
    path.write_text(src,encoding='utf-8')

if HTMLS[0].read_bytes()!=HTMLS[1].read_bytes():
    raise SystemExit('index/JOGAR divergiram no RT82.1')
print('RT82_1_PLAYERWORLDS_CLIENT_HARDENING_OK')
