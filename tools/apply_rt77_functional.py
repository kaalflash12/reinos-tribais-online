from pathlib import Path
import re, json, hashlib

root=Path.cwd()
files=['index.html','JOGAR_REINOS_TRIBAIS.html']
VERS='[17,18,19,20,21,22,23,24,25,49,50,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77]'

def must_replace(s, old, new, label, count=1):
    n=s.count(old)
    if n < count:
        raise SystemExit(f'{label}: expected >= {count}, found {n}')
    return s.replace(old,new,count)

ranked_fn=r'''  function renderRanked() {
    const d=CLOUD.eventData||{}, seasons=d.seasons||[], ratings=d.ratings||[], matches=d.matches||[], rewards=d.rankedRewards||[];
    if(!CLOUD.ready) return `<h1 class="panel-title">Arena Ranqueada</h1><section class="rt601-ranked-command"><div class="rt601-ranked-banner"><div><span class="tiny">RANKED ONLINE • TEMPORADAS</span><h2>Prove o poder do seu reino</h2><p>Partidas usam tropas sincronizadas, poder militar e rating. O resultado altera sua classificação e fica registrado no histórico.</p></div><button class="btn primary" data-cloud-login>Entrar para jogar Ranked</button></div></section>`;
    const active=seasons.find(x=>x.status==='active'&&Date.parse(x.starts_at)<=Date.now()&&Date.parse(x.ends_at)>Date.now());
    const finished=seasons.filter(x=>x.status==='finished'||Date.parse(x.ends_at)<=Date.now()).slice(0,12);
    const pending=rewards.filter(x=>x.status==='pending'&&(!x.expires_at||Date.parse(x.expires_at)>Date.now()));
    const rewardHtml=pending.length?`<h2 class="section-title">Recompensas pendentes</h2><div class="card-grid">${pending.map(r=>`<article class="game-card"><h3>🏆 Recompensa da temporada</h3><p>Colocação <b>#${r.rank||'—'}</b></p><p class="small">${escapeHtml(JSON.stringify(r.reward||{}))}</p><button class="btn primary" data-claim-ranked-reward="${r.id}">Resgatar recompensa</button></article>`).join('')}</div>`:'';
    const pastRows=finished.map(s=>{const rr=ratings.find(r=>r.season_id===s.id&&r.user_id===CLOUD.user?.id);const mm=matches.filter(m=>m.season_id===s.id&&(m.challenger_user_id===CLOUD.user?.id||m.opponent_user_id===CLOUD.user?.id));return `<tr><td>${escapeHtml(s.name)}</td><td>${new Date(s.ends_at).toLocaleDateString('pt-BR')}</td><td>${rr?nfmt(rr.rating):'—'}</td><td>${rr?`${rr.wins||0}/${rr.losses||0}`:'—'}</td><td>${mm.length}</td></tr>`}).join('');
    const past=`<h2 class="section-title">Temporadas anteriores</h2><div class="rt13-table-scroll"><table class="data-table"><thead><tr><th>Temporada</th><th>Fim</th><th>Rating</th><th>V/D</th><th>Partidas</th></tr></thead><tbody>${pastRows||'<tr><td colspan="5">Nenhuma temporada encerrada ainda.</td></tr>'}</tbody></table></div>${rewardHtml}`;
    if(!active) return `<h1 class="panel-title">Arena Ranqueada</h1><section class="rt601-ranked-command"><div class="notice">Nenhuma temporada ranqueada ativa neste mundo agora.</div>${past}</section>`;
    const rows=ratings.filter(x=>x.season_id===active.id).sort((a,b)=>Number(b.rating)-Number(a.rating));
    const me=rows.find(x=>x.user_id===CLOUD.user?.id)||{rating:1000,wins:0,losses:0,matches:0,streak:0};
    const pos=rows.findIndex(x=>x.user_id===CLOUD.user?.id), tier=rankedTier(me.rating);
    const myMatches=matches.filter(m=>m.season_id===active.id&&(m.challenger_user_id===CLOUD.user?.id||m.opponent_user_id===CLOUD.user?.id)).slice(0,20);
    const leaderboard=rows.slice(0,20).map((r,i)=>`<tr class="${r.user_id===CLOUD.user?.id?'rt60-ranked-me':''}"><td><b>#${i+1}</b></td><td>${escapeHtml(onlinePlayerName(r.user_id))}</td><td>${rankedTier(r.rating).icon} ${rankedTier(r.rating).name}</td><td><b>${nfmt(r.rating)}</b></td><td>${r.wins} / ${r.losses}</td><td>${r.streak>0?'🔥 +'+r.streak:r.streak<0?'❄ '+r.streak:'—'}</td></tr>`).join('');
    const history=myMatches.map(m=>{const opp=m.challenger_user_id===CLOUD.user?.id?m.opponent_user_id:m.challenger_user_id,won=m.winner_user_id===CLOUD.user?.id;return `<tr><td>${new Date(m.created_at).toLocaleString('pt-BR')}</td><td>${escapeHtml(onlinePlayerName(opp))}</td><td class="${won?'good':'bad'}"><b>${won?'VITÓRIA':'DERROTA'}</b></td><td>${won?'+':'−'}${Math.abs(Number(m.rating_delta)||0)}</td></tr>`}).join('');
    return `<h1 class="panel-title">Arena Ranqueada</h1><section class="rt601-ranked-command"><div class="rt601-ranked-banner"><div><span class="tiny">TEMPORADA ATIVA</span><h2>${escapeHtml(active.name)}</h2><p>${tier.icon} <b>${tier.name}</b> • Rating <strong>${nfmt(me.rating)}</strong> • posição <strong>${pos>=0?'#'+(pos+1):'não ranqueado'}</strong></p><small>Encerra em ${formatDuration(Math.max(0,Date.parse(active.ends_at)-Date.now()))}</small></div><button class="btn primary" data-play-ranked>⚔ BUSCAR ADVERSÁRIO</button></div><div class="rt601-ranked-columns"><article class="game-card"><h3>Classificação</h3><div class="rt13-table-scroll"><table class="data-table"><thead><tr><th>#</th><th>Governante</th><th>Tier</th><th>Rating</th><th>V/D</th><th>Sequência</th></tr></thead><tbody>${leaderboard||'<tr><td colspan="6">Nenhum jogador ranqueado ainda.</td></tr>'}</tbody></table></div></article><article class="game-card"><h3>Seu histórico</h3><div class="rt13-table-scroll"><table class="data-table"><thead><tr><th>Data</th><th>Adversário</th><th>Resultado</th><th>Δ Rating</th></tr></thead><tbody>${history||'<tr><td colspan="4">Sem partidas nesta temporada.</td></tr>'}</tbody></table></div></article></div>${past}</section>`;
  }
'''

for fn in files:
    p=root/fn
    s=p.read_text('utf-8')
    if 'const VERSION = 77;' in s and 'RT77_FULL_FUNCTIONAL_PATCH' in s:
        print(fn,'already RT77')
        continue
    s=must_replace(s,'const VERSION = 76;\n  const RT_BUILD = "76.2";','const VERSION = 77;\n  const RT_BUILD = "77.0";\n  const RT77_FULL_FUNCTIONAL_PATCH = true;',fn+' version')
    old='[17, 18, 19, 20, 21, 22, 23, 24, 25, 49, 50].includes(Number(parsed.version))'
    if s.count(old)!=2: raise SystemExit(f'{fn} save guards {s.count(old)}')
    s=s.replace(old,f'{VERS}.includes(Number(parsed.version))')

    anchor="""    const wid=encodeURIComponent(CLOUD.worldId),uid=encodeURIComponent(CLOUD.user.id);\n    try {\n"""
    inject=anchor+"""      if(Date.now()-Number(CLOUD.lastMaintenanceAt||0)>30000){\n        try{await cloudRequest('/rest/v1/rpc/rt77_world_maintenance',{method:'POST',body:{p_world_id:CLOUD.worldId},timeoutMs:12000});CLOUD.lastMaintenanceAt=Date.now();}\n        catch(e){console.error('RT77 manutenção do mundo',e);}\n      }\n"""
    s=must_replace(s,anchor,inject,fn+' maintenance anchor')
    s=must_replace(s,'const [events,progress,ent,seasons,ratings,matches,nodes,monsters,playerRows]=await Promise.all([','const [events,progress,ent,seasons,ratings,matches,nodes,monsters,playerRows,rankedRewards]=await Promise.all([',fn+' meta array')
    s=must_replace(s,"cloudRequest(`/rest/v1/player_worlds?world_id=eq.${wid}&user_id=eq.${uid}&select=*&limit=1`)\n      ]);","cloudRequest(`/rest/v1/player_worlds?world_id=eq.${wid}&user_id=eq.${uid}&select=*&limit=1`),\n        cloudRequest(`/rest/v1/player_event_rewards?world_id=eq.${wid}&user_id=eq.${uid}&event_id=is.null&select=*&order=created_at.desc&limit=100`)\n      ]);",fn+' rewards fetch')
    s=must_replace(s,'matches:matches||[],nodes:nodes||[],monsters:monsters||[]','matches:matches||[],nodes:nodes||[],monsters:monsters||[],rankedRewards:rankedRewards||[]',fn+' eventData')
    s=s.replace("['events','ranked','map','overview','inventory'].includes(currentView)","['events','ranked','map','overview','inventory','rally'].includes(currentView)",1)

    event_claim="""  async function claimEventReward(id) {\n    try{const r=await cloudRequest('/rest/v1/rpc/rt50_claim_event_rewards',{method:'POST',body:{p_event_id:id},timeoutMs:12000});toast(`Recompensa resgatada • posição #${r.rank}`,'success');await pollMultiplayer(false);await refreshOnlineMeta(false);renderAll();}catch(e){toast(e.message||'Não foi possível resgatar.','error');}\n  }\n"""
    ranked_claim=event_claim+"""\n  async function claimRankedReward(id) {\n    try{const r=await cloudRequest('/rest/v1/rpc/rt77_claim_ranked_reward',{method:'POST',body:{p_reward_id:id},timeoutMs:12000});toast(`Recompensa ranqueada resgatada${r?.rank?' • posição #'+r.rank:''}.`,'success');await pollMultiplayer(false);await refreshOnlineMeta(false);renderAll();}\n    catch(e){toast(e.message||'Não foi possível resgatar a recompensa ranqueada.','error');}\n  }\n"""
    s=must_replace(s,event_claim,ranked_claim,fn+' ranked claim')

    a=s.index('  function renderRanked() {'); b=s.index('\n  function renderEvents() {',a)
    s=s[:a]+ranked_fn+s[b:]

    a=s.index('  function recallSupport(supportId,targetId) {'); b=s.index('\n  function ',a+5)
    old_recall=s[a:b]
    local_body=old_recall.replace('  function recallSupport(supportId,targetId) {','')
    local_body=re.sub(r'^\s*const target=.*?; if\(!support\)return;\s*', '', local_body, count=1, flags=re.S)
    new_recall="""  async function recallSupport(supportId,targetId) {\n    const target=state.villages[targetId], support=target?.supports?.find(s=>String(s.id)===String(supportId)); if(!support)return;\n    const cloudSource=villageByCloudId(support.sourceId); const online=Boolean(support.online||support.sourceUserId===CLOUD.user?.id||cloudSource?._cloudVillageId);\n    if(online){if(!CLOUD.ready)return toast('Conecte sua conta para retirar este apoio online.','error');try{await cloudRequest('/rest/v1/rpc/rt77_recall_support',{method:'POST',body:{p_world_id:CLOUD.worldId,p_support_id:supportId},timeoutMs:12000});toast('Apoio online chamado de volta.','success');await pollMultiplayer(false);await refreshOnlineMeta(false);renderAll();}catch(e){toast(e.message||'Não foi possível retirar o apoio online.','error');}return;}\n"""+local_body
    s=s[:a]+new_recall+s[b:]

    old="""${(v.supports||[]).length?`<h3>Apoios estacionados aqui</h3>${v.supports.map(s=>`<div class="queue-item"><span>De ${escapeHtml(state.villages[s.sourceId]?.name||'aldeia')} • ${Object.entries(s.units).filter(([,q])=>q>0).map(([k,q])=>`${D.units[k].icon}${nfmt(q)}`).join(' ')}</span>${state.villages[s.sourceId]?.owner==='player'?`<button class="btn small-btn" data-recall-support="${s.id}:${v.id}">Retirar</button>`:''}</div>`).join('')}`:''}"""
    new="""${(v.supports||[]).length?`<h3>Apoios estacionados aqui</h3>${v.supports.map(s=>{const src=state.villages[s.sourceId]||villageByCloudId(s.sourceId), sourceName=s.sourceName||src?.name||'aldeia', canRecall=src?.owner==='player'||s.sourceUserId===CLOUD.user?.id;return `<div class="queue-item"><span>De ${escapeHtml(sourceName)} • ${Object.entries(s.units).filter(([,q])=>q>0).map(([k,q])=>`${D.units[k].icon}${nfmt(q)}`).join(' ')}</span>${canRecall?`<button class="btn small-btn" data-recall-support="${s.id}:${v.id}">Retirar</button>`:''}</div>`}).join('')}`:''}"""
    s=must_replace(s,old,new,fn+' support UI')

    hook="const claimEventBtn=event.target.closest('[data-claim-event]'); if(claimEventBtn){ void claimEventReward(claimEventBtn.dataset.claimEvent); return; }"
    s=must_replace(s,hook,hook+"\n    const claimRankedBtn=event.target.closest('[data-claim-ranked-reward]'); if(claimRankedBtn){ void claimRankedReward(claimRankedBtn.dataset.claimRankedReward); return; }",fn+' ranked hook')
    s=s.replace("if (recallBtn) { const [sid,tid]=recallBtn.dataset.recallSupport.split(':'); return recallSupport(sid,tid); }","if (recallBtn) { const [sid,tid]=recallBtn.dataset.recallSupport.split(':'); void recallSupport(sid,tid); return; }",1)
    s=s.replace("window.RT76={version:'76.1'","window.RT76={version:'77.0'",1)
    rtline=next((line for line in s.splitlines() if line.lstrip().startswith("window.RT76={version:'77.0'")),None)
    if rtline and 'window.RT77 = window.RT76;' not in s:
        s=s.replace(rtline,rtline+'\n  window.RT77 = window.RT76;',1)
    s=s.replace('rt76-runtime.js?v=76.2','rt76-runtime.js?v=77.0').replace('rt76-map-ai.js?v=76.2','rt76-map-ai.js?v=77.0').replace('rt76-master-plan.js?v=76.2','rt76-master-plan.js?v=77.0')
    p.write_text(s,'utf-8')
    print(fn,hashlib.sha256(p.read_bytes()).hexdigest())

audit={
 'build':'RT77.0','base':'RT76.2','global_claim':'Only verified items are marked PASS.',
 'fixed':['save/load/import accepts current RT77','online support recall and return','automatic world maintenance','ranked season history and reward claim','mutation RPC anon hardening'],
 'preserved':['RT64 admin','RT66 guided no-code admin','19 building scene','Paladin rename','inventory usable items','world merchants/monsters/bosses'],
 'backend_migrations':['rt77_support_recall_ranked_claim_maintenance','rt77_fix_ranked_reward_units_ambiguity'],
 'database_tests':['market create/accept rollback PASS','support send/arrive/recall/return rollback PASS','ranked play rollback PASS','ranked reward claim rollback PASS','inventory consume rollback PASS','merchant purchase rollback PASS','boss shared HP rollback PASS']
}
(root/'AUDITORIA_RT77.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),'utf-8')
(root/'RT77_README.txt').write_text('REINOS TRIBAIS RT77.0\n\nBase RT76.2. Mantém RT64/RT66 e corrige persistência da versão atual, retirada de apoio online, manutenção automática do mundo e recompensas ranqueadas.\n','utf-8')

if (root/'index.html').read_bytes()!=(root/'JOGAR_REINOS_TRIBAIS.html').read_bytes():
    raise SystemExit('HTML files diverged')
print('HTML_SHA256',hashlib.sha256((root/'index.html').read_bytes()).hexdigest())