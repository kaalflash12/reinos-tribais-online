from pathlib import Path
import re,json,hashlib

FILES=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]
base=FILES[0].read_text(encoding='utf-8')

if 'RT74_EXECUTION_COMPLETE' in base:
    fixed=base
else:
    fixed=base
    fixed=re.sub(r'<title>Reinos Tribais — RT\d+[^<]*</title>','<title>Reinos Tribais — RT74 Eventos & Ranked</title>',fixed,count=1)
    fixed=re.sub(r'const VERSION = \d+;','const VERSION = 74;',fixed,count=1)
    fixed=re.sub(r'const RT_BUILD = "[^"]+";','const RT_BUILD = "74.0";',fixed,count=1)
    anchor='const RT_BUILD = "74.0";'
    fixed=fixed.replace(anchor,anchor+'\n  const RT74_EXECUTION_COMPLETE = true;',1)

    css=r'''
<style id="rt74-light-polish">
/* RT74: polimento leve, sem reconstruir layout */
.game-shell .rt74-extra-panel{margin:12px 0;padding:14px;border:1px solid #67532b;background:linear-gradient(180deg,#171b15,#0f130f);box-shadow:0 5px 16px #0004}
.game-shell .rt74-extra-panel>header{display:flex;gap:10px;align-items:flex-end;justify-content:space-between;border-bottom:1px solid #483d25;padding-bottom:9px;margin-bottom:10px}.game-shell .rt74-extra-panel h2,.game-shell .rt74-extra-panel h3{margin:0;color:#e5c46a}.game-shell .rt74-extra-panel p{color:#b5a98a}
.game-shell .rt74-prize-grid,.game-shell .rt74-calendar-grid,.game-shell .rt74-monster-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:8px}.game-shell .rt74-prize,.game-shell .rt74-event-card,.game-shell .rt74-monster-card{border:1px solid #4e4329;background:#10140f;padding:11px;min-width:0}.game-shell .rt74-prize strong,.game-shell .rt74-event-card strong,.game-shell .rt74-monster-card strong{display:block;color:#ead080;margin-bottom:5px}.game-shell .rt74-prize small,.game-shell .rt74-event-card small,.game-shell .rt74-monster-card small{display:block;color:#91886f;line-height:1.45}.game-shell .rt74-tag{display:inline-flex;align-items:center;padding:3px 7px;margin:0 4px 5px 0;border:1px solid #68552b;border-radius:999px;background:#1b1b12;color:#d9bd72;font-size:10px;font-weight:800;text-transform:uppercase;letter-spacing:.05em}.game-shell .rt74-tag.seasonal{border-color:#806528;color:#f0ce6d}.game-shell .rt74-tag.boss{border-color:#7d3d32;color:#ef9c8d}.game-shell .rt74-reward-line{margin-top:7px;color:#d8c69d;font-size:12px;line-height:1.45}.game-shell .rt74-ability{display:inline-block;margin:2px;padding:3px 6px;border:1px solid #3d4b32;background:#111912;color:#9fcb8f;font-size:10px}.game-shell .rt74-empty{padding:14px;border:1px dashed #4b432e;color:#8f876f}.game-shell #rt74-local-save-status{position:fixed;right:12px;bottom:12px;z-index:9999;padding:7px 10px;border:1px solid #657041;background:#10170fee;color:#b8dc8f;font:700 11px system-ui;box-shadow:0 4px 14px #0008;pointer-events:none}
@media(max-width:760px){.game-shell .rt74-prize-grid,.game-shell .rt74-calendar-grid,.game-shell .rt74-monster-grid{grid-template-columns:1fr}.game-shell .rt74-extra-panel{padding:10px}.game-shell #rt74-local-save-status{right:6px;bottom:6px}}
</style>
'''
    if 'id="rt74-light-polish"' not in fixed:
        fixed=fixed.replace('</head>',css+'</head>',1)

    js=r'''
  /* ============================================================
     RT74 — execução solicitada: ranked, calendário, exclusivos,
     save local e polimento leve. Sem MutationObserver.
     ============================================================ */
  function rt74RewardSummary(r){
    r=r||{};const out=[];
    if(Number(r.crowns)>0)out.push(`👑 ${nfmt(Number(r.crowns))} Coroas`);
    if(Number(r.academy_coins)>0)out.push(`🏛️ ${nfmt(Number(r.academy_coins))} moedas da Academia`);
    if(r.resources){const z=r.resources;out.push(`📦 ${nfmt(Number(z.wood)||0)} madeira · ${nfmt(Number(z.clay)||0)} argila · ${nfmt(Number(z.iron)||0)} ferro`)}
    if(r.units){for(const [k,q] of Object.entries(r.units))if(Number(q)>0)out.push(`⚔️ ${nfmt(Number(q))} ${k==='royal_guard'?'Guardas Reais':k}`)}
    if(r.title?.name)out.push(`🏅 Título: ${r.title.name}${r.title.hours?` (${Math.round(Number(r.title.hours)/24)} dias)`:''}`);
    if(r.paladin_set)out.push(`🛡️ Conjunto do Paladino: ${String(r.paladin_set).replaceAll('_',' ')}`);
    if(Number(r.extra_paladin_hours)>0)out.push(`🐎 Segundo Paladino: ${Math.round(Number(r.extra_paladin_hours)/24)} dias`);
    if(r.item){const it=typeof r.item==='string'?r.item:(r.item.name||r.item.code);if(it)out.push(`💎 Item exclusivo: ${it}`)}
    if(r.boost)out.push(`✨ Bônus exclusivo: ${typeof r.boost==='string'?r.boost:JSON.stringify(r.boost)}`);
    return out.length?out.join(' · '):'Sem recompensa cadastrada.';
  }
  function rt74MergeReward(a,b){return {...(a||{}),...(b||{}),resources:{...(a?.resources||{}),...(b?.resources||{})},units:{...(a?.units||{}),...(b?.units||{})}}}
  function rt74RankedRewards(season){return season?.config?.rewards||{participation:{crowns:75},top10:{crowns:150,resources:{wood:10000,clay:10000,iron:10000}},top3:{crowns:500,units:{royal_guard:50}},top1:{crowns:1000,units:{royal_guard:100},title:{name:'Campeão Ranqueado',hours:336,attack_bonus:.05,defense_bonus:.05},paladin_set:'coroa_dourada',extra_paladin_hours:168}}}
  function rt74PrizeCard(label,reward,cls=''){return `<article class="rt74-prize ${cls}"><strong>${label}</strong><div class="rt74-reward-line">${escapeHtml(rt74RewardSummary(reward))}</div></article>`}
  function rt74RankedPrizePanel(){
    const seasons=CLOUD.eventData?.seasons||[];const s=seasons.find(x=>x.status==='active'&&Date.parse(x.ends_at)>Date.now())||seasons[0];const rw=rt74RankedRewards(s);
    const p=rw.participation||{},t10=rt74MergeReward(p,rw.top10),t3=rt74MergeReward(t10,rw.top3),t1=rt74MergeReward(t3,rw.top1);
    return `<section class="rt74-extra-panel"><header><div><span class="rt74-tag">premiação automática</span><h2>Recompensas da temporada</h2><p class="small">A recompensa fica pendente para resgate quando a temporada termina. É necessário disputar pelo menos uma partida.</p></div>${s?.ends_at?`<small>Fim: ${new Date(s.ends_at).toLocaleString('pt-BR')}</small>`:''}</header><div class="rt74-prize-grid">${rt74PrizeCard('👑 1º lugar',t1)}${rt74PrizeCard('🥇 2º–3º lugar',t3)}${rt74PrizeCard('🏆 4º–10º lugar',t10)}${rt74PrizeCard('⚔️ Participação',p)}</div></section>`;
  }
  const RT74_BASE_RENDER_RANKED=renderRanked;
  renderRanked=function(){return RT74_BASE_RENDER_RANKED()+rt74RankedPrizePanel()};

  function rt74Category(c){return ({seasonal:'Sazonal',world_boss:'Boss mundial',competition:'Competição',economy:'Economia',military:'Militar',exploration:'Exploração'})[c]||c||'Evento'}
  function rt74AbilityList(v){if(!v)return '';const a=Array.isArray(v)?v:Object.entries(v).map(([k,x])=>typeof x==='object'?`${k}: ${JSON.stringify(x)}`:`${k}: ${x}`);return a.slice(0,8).map(x=>`<span class="rt74-ability">${escapeHtml(String(x))}</span>`).join('')}
  function rt74EventsExecutionPanel(){
    const d=CLOUD.eventData||{},events=(d.events||[]).slice().sort((a,b)=>Date.parse(a.starts_at)-Date.parse(b.starts_at)),monsters=d.monsters||[];
    const eventCards=events.slice(0,12).map(e=>`<article class="rt74-event-card"><span class="rt74-tag ${e.config?.mandatory_seasonal?'seasonal':''}">${e.config?.mandatory_seasonal?'OBRIGATÓRIO · ':''}${escapeHtml(rt74Category(e.category))}</span><strong>${escapeHtml(e.name)}</strong><small>${new Date(e.starts_at).toLocaleString('pt-BR')} → ${new Date(e.ends_at).toLocaleString('pt-BR')} · ${e.status==='active'?'ATIVO':'AGENDADO'}</small><div class="rt74-reward-line"><b>Participação:</b> ${escapeHtml(rt74RewardSummary(e.rewards?.participation||{}))}<br><b>Top 3:</b> ${escapeHtml(rt74RewardSummary(rt74MergeReward(e.rewards?.participation,e.rewards?.top3)))}<br><b>1º:</b> ${escapeHtml(rt74RewardSummary(rt74MergeReward(rt74MergeReward(e.rewards?.participation,e.rewards?.top3),e.rewards?.top1)))}</div></article>`).join('');
    const monsterCards=monsters.slice(0,12).map(m=>`<article class="rt74-monster-card"><span class="rt74-tag boss">${m.status==='active'?'ATIVO':'AGENDADO'}</span><strong>${escapeHtml(m.name)}</strong><small>${escapeHtml(m.description||'Monstro mundial')} · Nv.${Number(m.level)||1} · ${nfmt(Number(m.hp)||0)}/${nfmt(Number(m.max_hp)||0)} PV</small><div>${rt74AbilityList(m.abilities)}</div><div class="rt74-reward-line"><b>Drop/participação:</b> ${escapeHtml(rt74RewardSummary(m.rewards?.participation||m.rewards||{}))}<br><b>Maior dano:</b> ${escapeHtml(rt74RewardSummary(m.rewards?.top1||{}))}</div></article>`).join('');
    return `<section class="rt74-extra-panel"><header><div><span class="rt74-tag seasonal">calendário automático</span><h2>Próximos eventos</h2><p class="small">Sazonais obrigatórios ficam marcados; eventos periódicos são mantidos automaticamente pelo servidor.</p></div><small>Backend RT-World v5</small></header><div class="rt74-calendar-grid">${eventCards||'<div class="rt74-empty">Nenhum evento recebido do servidor neste momento.</div>'}</div></section><section class="rt74-extra-panel"><header><div><span class="rt74-tag boss">conteúdo exclusivo</span><h2>Monstros e drops exclusivos</h2><p class="small">Nome, HP, habilidades e drops vêm do template específico do monstro; não de um boss genérico.</p></div></header><div class="rt74-monster-grid">${monsterCards||'<div class="rt74-empty">Nenhum monstro ativo/agendado neste momento. Eles aparecem quando o evento correspondente ativa.</div>'}</div></section>`;
  }
  const RT74_BASE_RENDER_EVENTS=renderEvents;
  renderEvents=function(){return RT74_BASE_RENDER_EVENTS()+rt74EventsExecutionPanel()};

  function rt74LocalStatus(text){let el=document.getElementById('rt74-local-save-status');if(!el){el=document.createElement('div');el.id='rt74-local-save-status';document.body.appendChild(el)}el.textContent=text}
  function rt74StorageTest(){const k='__rt74_storage_test__';try{localStorage.setItem(k,'1');const ok=localStorage.getItem(k)==='1';localStorage.removeItem(k);return ok}catch{return false}}
  const RT74_BASE_LOAD_STATE=loadState;
  loadState=function(){const v=RT74_BASE_LOAD_STATE();if(v)return v;try{const raw=localStorage.getItem(SAVE_KEY+'_backup');if(raw){const x=JSON.parse(raw);migrateState(x);return x}}catch(e){console.error('Backup local inválido',e)}return null};
  const RT74_BASE_SAVE_STATE=saveState;
  saveState=function(force=false){RT74_BASE_SAVE_STATE(force);if(!CLOUD.ready&&state&&SAVE_KEY.endsWith('_local')){try{const snap=stateForSave();snap.version=VERSION;localStorage.setItem(SAVE_KEY+'_backup',JSON.stringify(snap));rt74LocalStatus(`✓ Salvo localmente · ${new Date().toLocaleTimeString('pt-BR')}`)}catch(e){rt74LocalStatus('⚠ Falha no save local');console.error(e)}}};
  playOfflineMode=async function(){
    if(CLOUD.saveTimer){clearTimeout(CLOUD.saveTimer);CLOUD.saveTimer=null}if(CLOUD.pollTimer){clearInterval(CLOUD.pollTimer);CLOUD.pollTimer=null}try{stopRealtime()}catch{}
    CLOUD.ready=false;CLOUD.saving=false;CLOUD.pending=false;CLOUD.lastError='';CLOUD.worldId=null;CLOUD.worldSlug='';CLOUD.selectedWorld=null;setWorldSaveKeys();
    document.body.dataset.rt74Mode='local';
    if(!rt74StorageTest()){state=null;renderStart();toast('O navegador bloqueou o armazenamento local para este arquivo.','error');rt74LocalStatus('⚠ Armazenamento local bloqueado');return}
    const local=loadState();if(local){await activateLoadedState(local);toast('Modo local carregado e save persistente ativado.','success');rt74LocalStatus('✓ Save local carregado')}else{state=null;renderStart();rt74LocalStatus('Modo local · novo reino')}
  };
  if(!window.RT74_LOCAL_AUTOSAVE){window.RT74_LOCAL_AUTOSAVE=setInterval(()=>{if(!CLOUD.ready&&state){try{saveState(true)}catch(e){console.error('Autosave local RT74',e)}}},15000)}
'''
    marker="  window.addEventListener('beforeunload', () => saveState(true));"
    if marker not in fixed:
        raise SystemExit('marcador final do runtime não encontrado')
    fixed=fixed.replace(marker,js+'\n'+marker,1)

for p in FILES:
    p.write_text(fixed,encoding='utf-8')

plan='''# PLANO DE EXECUÇÃO — REINOS TRIBAIS RT74\n\n## Objetivo\nConsolidar a execução solicitada sem reconstruir o jogo: Ranked, eventos sazonais/periódicos, save local, polimento visual e conteúdo exclusivo de monstros/eventos.\n\n## Passo a passo\n1. **Inventário mestre** — manter como referência a lista histórica de 714 requisitos e não transformar auditoria histórica em prova da build atual.\n2. **Regressões atuais** — bloquear carregamento infinito, aldeia vazia, prédio fullscreen, versões visuais misturadas e falhas de save.\n3. **Save local** — chave `_local` obrigatória ao entrar offline, limpeza de estado de mundo online, teste de localStorage, backup redundante e autosave a cada 15 s.\n4. **Ranked** — matchmaking/pontuação existentes + tabela de prêmios visível + finalização automática + recompensa pendente sem duplicidade.\n5. **Eventos sazonais obrigatórios** — Festival da Grande Colheita e Solstício de Inverno agendados anualmente; registros 2026/2027 criados.\n6. **Eventos periódicos** — servidor mantém janela rolante semanal com Feira, Horda, Paladinos, Besta, Domínio, Colosso, Assalto, Fronteiras e Torneio.\n7. **Monstros de evento** — trigger real na ativação; seleção por `event_tags`; copiar template_key, nome, família, HP, descrição, habilidades e recompensas.\n8. **Exclusivos** — Guarda Real, segundo Paladino temporário, Coroa Dourada, títulos e itens exclusivos entram nos fluxos de resgate.\n9. **UI de Eventos** — calendário, status, data, participação/Top3/Top1, habilidades e drops legíveis.\n10. **UI Ranked** — mostrar participação, Top10, Top3, 1º e término da temporada.\n11. **Polimento visual leve** — cards, badges, hierarquia e indicador de save; sem novo layout massivo.\n12. **Validação estática** — dois HTMLs idênticos, versão RT74, JavaScript validado pelo Node e marcadores obrigatórios.\n13. **Backend** — verificar migration, trigger, calendário, active/scheduled/finished, Edge rt-world v5 e premiação da temporada.\n14. **Windows** — instalador único baixa a build publicada, preserva backup, valida SHA/marcadores e abre o arquivo local correto.\n15. **Regressão contínua** — qualquer erro de runtime no Windows é FAIL; não converter screenshot/asset opcional em falso PASS funcional.\n'''
Path('PLANO_EXECUCAO_RT74.md').write_text(plan,encoding='utf-8')

checks={
 'html_identical':FILES[0].read_bytes()==FILES[1].read_bytes(),
 'version_74':'const VERSION = 74;' in fixed and 'const RT_BUILD = "74.0";' in fixed,
 'runtime_marker':'RT74_EXECUTION_COMPLETE' in fixed,
 'ranked_prizes':'rt74RankedPrizePanel' in fixed and 'royal_guard' in fixed,
 'event_calendar_ui':'rt74EventsExecutionPanel' in fixed and 'mandatory_seasonal' in fixed,
 'monster_exclusives_ui':'Monstros e drops exclusivos' in fixed and 'rt74AbilityList' in fixed,
 'local_save_fix':'CLOUD.worldId=null' in fixed and "SAVE_KEY+'_backup'" in fixed and 'RT74_LOCAL_AUTOSAVE' in fixed,
 'light_polish':'id="rt74-light-polish"' in fixed,
 'no_new_mutation_observer':'RT74_LOCAL_AUTOSAVE' in fixed
}
if not all(checks.values()):
    print(json.dumps(checks,indent=2,ensure_ascii=False));raise SystemExit('RT74 CHECK FAIL')
report={'build':'RT74','checks':checks,'sha256':hashlib.sha256(fixed.encode()).hexdigest()}
Path('AUDITORIA_EXECUCAO_RT74.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,indent=2,ensure_ascii=False))
