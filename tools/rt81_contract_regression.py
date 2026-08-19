from pathlib import Path
import json,re,sys

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
edge=text('backend/rt81-multiplayer-safe.ts')
lock=text('backend/rt81-lock-raw-gameplay.sql')
indexes=text('backend/rt81-security-and-transfer-indexes.sql')

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
must('edge poll security revision',"security_revision:'rt81'" in edge)
must('edge public villages exclude private columns','select=id,owner_user_id,owner_kind,owner_name,tribe_name,name,x,y,points,updated_at' in edge)
must('edge public world query does not request private columns',not re.search(r'world=await db\(`villages\?[^`]*select=[^`]*(?:resources|units|build_queue|recruit_queue)',edge))
must('incoming sanitized below watchtower 15',"payload:lvl>=15?" in edge and "visibility='composition'" in edge)
must('raw commands select locked to owner','commands_select_own' in lock and 'owner_user_id' in lock)
must('raw villages select locked to owner','villages_select_own' in lock and 'owner_user_id' in lock)
must('raw player profile select locked to owner','player_worlds_select_own' in lock and 'user_id' in lock)
must('transfer source index versioned','rt79_resource_transfers_source_idx' in indexes)
must('transfer target index versioned','rt79_resource_transfers_target_idx' in indexes)

out={'build':'RT80.5+RT81','pass':True,'checks':checks,'count':len(checks)}
proof=ROOT/'RT81_CONTRACT_REGRESSION.json'
proof.write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(out,ensure_ascii=False,indent=2))
