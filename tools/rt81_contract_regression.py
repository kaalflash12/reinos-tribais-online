from pathlib import Path
import json,re

ROOT=Path(__file__).resolve().parents[1]
checks=[]

def must(name,cond,detail=''):
    checks.append({'name':name,'pass':bool(cond),'detail':detail})
    if not cond:
        raise AssertionError(f'{name}: {detail}')

def text(path):
    return (ROOT/path).read_text(encoding='utf-8')

suite=text('rt79-suite.js')
security=text('rt81-security-runtime.js')
bootstrap=text('rt79-village-ui.js')
edge=text('backend/rt81-multiplayer-safe.ts')
lock=text('backend/rt81-lock-raw-gameplay.sql')
indexes=text('backend/rt81-security-and-transfer-indexes.sql')
strategy=[text(f'backend/rt81/{i:02d}_{name}.sql') for i,name in [
    (1,'incoming_intel'),(2,'process_automations'),(3,'dashboard_watchtower'),(4,'dashboard_logistics_ai'),
    (5,'transfer_tick'),(6,'atomic_batch_planner'),(7,'market_autotrade'),(8,'farm_recommend'),(9,'farm_batch_smart'),
    (10,'incoming_realtime_signal')
]]
strategy_all='\n'.join(strategy)
signal_norm=re.sub(r'\s+','',strategy[9])

must('planner atomic RPC wired','rt81_schedule_batch' in suite)
must('multi-target selector wired','name="batchTargets"' in suite and 'targetGap' in suite)
must('50-order client guard','orders.length>50' in suite)
must('farm single-target server model','data-rt81-farm-target' in suite and 'recommended_model' in suite)
must('farm threat/confidence/cooldown visible',all(x in suite for x in ['threat_level','confidence','cooldown_seconds']))
must('market per-resource reserve',all(x in suite for x in ['min_wood','min_clay','min_iron']))
must('market per-resource target',all(x in suite for x in ['target_wood','target_clay','target_iron']))
must('market per-resource ratio',all(x in suite for x in ['ratio_wood','ratio_clay','ratio_iron']))
must('real transfers visible','resource_transfers' in suite and 'Remessas reais' in suite)
must('group goals UI connected','groupGoals' in suite and 'rt79-group-goal-form' in suite)
must('safe world directory RPC','rt81_world_directory' in security)
must('enemy projection disclosure','_publicVisualProjection' in security and 'Inteligência protegida' in security)
must('incoming realtime runtime subscription',all(x in security for x in ['rt81_incoming_signals','initIncomingSignalRealtime','scheduleIncomingPoll','rt81IncomingSignalChannel']))
must('incoming realtime wakes sanitized poll','window.pollMultiplayer(false)' in security)
must('security runtime cache-buster current','rt81-security-runtime.js?v=81.3' in bootstrap and "version:'81.3'" in security)
must('edge poll security revision',"security_revision:'rt81.4'" in edge)
must('edge public villages exclude private columns','select=id,owner_user_id,owner_kind,owner_name,tribe_name,name,x,y,points,updated_at' in edge)
must('edge public world query does not request private columns',not re.search(r'world=await db\(`villages\?[^`]*select=[^`]*(?:resources|units|build_queue|recruit_queue)',edge))
must('incoming sanitized below watchtower 15',"payload:lvl>=15?" in edge and "visibility='composition'" in edge)
must('ensure village implemented directly','async function ensureVillage' in edge and "action==='ensure_village'" in edge and 'await ensureVillage' in edge)
must('sync village implemented directly','async function syncVillage' in edge and "action==='sync_village'" in edge and 'await syncVillage' in edge)
must('only attack is proxied to legacy chain','async function proxyAttack' in edge and "action==='send_attack'" in edge and 'proxyAttack(req,body)' in edge)
must('legacy due pass restored','async function resolveLegacyDue' in edge and 'rt81_due_pass:true' in edge)
must('legacy due pass is finite',"if(action==='poll'){if(!body.rt81_due_pass)await resolveLegacyDue(req,body);return out(await poll(u,wid))}" in edge)
must('generic legacy proxy removed','async function proxy(req,body)' not in edge and 'return await proxy(req,body)' not in edge)
must('raw commands select locked to owner','commands_select_own' in lock and 'owner_user_id' in lock)
must('raw villages select locked to owner','villages_select_own' in lock and 'owner_user_id' in lock)
must('raw player profile select locked to owner','player_worlds_select_own' in lock and 'user_id' in lock)
must('transfer source index versioned','rt79_resource_transfers_source_idx' in indexes)
must('transfer target index versioned','rt79_resource_transfers_target_idx' in indexes)
must('ten RT81 strategy SQL parts versioned',len(strategy)==10 and all(x.strip() for x in strategy))
must('route automation uses in-transit transfer','rt79_enqueue_transfer_internal' in strategy[1] and 'routes_dispatched' in strategy[1])
must('farm generic intel exclusion versioned',"<> 'farm'" in strategy[1])
must('watchtower helper versioned','private.rt81_incoming_intel' in strategy[0] and "lvl>=15" in strategy[0])
must('atomic batch SQL versioned','public.rt81_schedule_batch' in strategy[5] and 'n>50' in strategy[5])
must('per-resource autotrade SQL versioned',all(x in strategy[6] for x in ['min_cfg','target_cfg','ratio_cfg']))
must('farm recommendation SQL versioned',all(x in strategy[7] for x in ['threat_level','cooldown_seconds','confidence','recommended_model']))
must('smart farm uses unified recommender','rt79_farm_recommend' in strategy[8])
must('incoming signal table has no private gameplay columns',all(x in strategy[9] for x in ['rt81_incoming_signals','target_user_id','target_village_id','arrives_at']) and all(x not in strategy[9].split('create or replace function private.rt81_sync_incoming_signal')[0] for x in ['troops jsonb','payload jsonb','resources jsonb','buildings jsonb']))
must('incoming signal RLS is owner-only','rt81_incoming_signal_own' in strategy[9] and 'using((selectauth.uid())=target_user_id)' in signal_norm)
must('incoming signal trigger lifecycle versioned','rt81_commands_incoming_signal_trg' in strategy[9] and "tg_op='DELETE'" in strategy[9] and "not like 'outbound%'" in strategy[9])
must('incoming signal added to Supabase realtime publication','supabase_realtime add table public.rt81_incoming_signals' in strategy[9])

out={'build':'RT80.5+RT81.4','pass':True,'checks':checks,'count':len(checks)}
proof=ROOT/'RT81_CONTRACT_REGRESSION.json'
proof.write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False,indent=2))
