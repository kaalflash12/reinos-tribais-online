from pathlib import Path
import json,re,sys

ROOT=Path(__file__).resolve().parents[1]
preview=(ROOT/'supabase/functions/rt-multiplayer-v82/index.ts').read_text(encoding='utf-8')
legacy=(ROOT/'backend/rt81-multiplayer-safe.ts').read_text(encoding='utf-8')
html=(ROOT/'index.html').read_text(encoding='utf-8')
checks=[]

def ck(name,cond,detail=''):
    checks.append({'name':name,'pass':bool(cond),'detail':detail})
    return bool(cond)

def section(src,start,end):
    a=src.find(start); b=src.find(end,a+len(start)) if a>=0 else -1
    return src[a:b if b>=0 else None] if a>=0 else ''

sync=section(preview,'async function syncVillage','function publicBuildings')
ensure=section(preview,'async function ensureVillage','async function progressOwn')
spawn=section(preview,'function canonicalSpawn','async function access')

ck('preview versioned',bool(preview.strip()))
ck('preview has canonical spawn','function canonicalSpawn' in preview)
ck('three explicit profiles',all(x in preview for x in ["'balanced'","'economy'","'military'"]))
ck('spawn resets mutable queues',all(x in spawn for x in ['build_queue:[]','recruit_queue:[]','supports:[]','unit_research_queue:[]']))
ck('spawn canonicalizes resources',all(x in spawn for x in ['wood:1200','wood:1800','wood:1500']))
ck('additional free village blocked',"if((own||[]).length>0)throw new Error('Criação adicional de aldeia não é permitida" in ensure)
ck('allocator ignores client x/y','v.x' not in ensure and 'v.y' not in ensure and 'allocateCoord' in ensure)
ck('sync updates metadata only',all(x in sync for x in ['name:cleanName','client_key']) and 'sane(' not in sync)
sensitive=['points','loyalty','buildings','units','resources','build_queue','recruit_queue','unit_research','unit_research_queue','scavenging','flag','militia_called']
ck('sync never copies sensitive client fields',all(re.search(rf'\bv\.{re.escape(x)}\b',sync) is None for x in sensitive),detail=','.join(x for x in sensitive if re.search(rf'\bv\.{re.escape(x)}\b',sync)))
ck('poll progresses queues server-side',"rpcAsUser(req,'rt82_progress_state'" in preview)
ck('poll produces resources server-side',"rpcAsUser(req,'rt82_produce_resources'" in preview)
ck('attack remains legacy delegated','rt-multiplayer-v59' in preview and "action==='send_attack'" in preview)
ck('preview JWT-derived auth required in code','const u=user(req);if(!u?.sub)' in preview)

legacy_tunnel=('function sane(' in legacy and 'const b=sane(v,cur.name)' in legacy)
routed_to_preview='rt-multiplayer-v82' in html
readiness={
  'legacy_sync_tunnel_closed': not legacy_tunnel,
  'browser_routed_to_preview': routed_to_preview,
  'ready_for_promotion': (not legacy_tunnel) and routed_to_preview
}

preview_pass=all(x['pass'] for x in checks)
out={'build':'RT82 authority preview','preview_pass':preview_pass,'readiness':readiness,'checks':checks}
(ROOT/'RT82_AUTHORITY_REGRESSION.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False,indent=2))
if not preview_pass: sys.exit(1)
if not readiness['ready_for_promotion']:
    print('RT82_PREVIEW_OK_BUT_PROMOTION_BLOCKED',file=sys.stderr)
    sys.exit(2)
