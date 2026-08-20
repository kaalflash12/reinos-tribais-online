from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
HTMLS=[ROOT/'index.html',ROOT/'JOGAR_REINOS_TRIBAIS.html']


def once(src,old,new,label):
    if new in src:
        return src
    count=src.count(old)
    if count!=1:
        raise SystemExit(f'{label}: esperado 1 ocorrência, encontrado {count}')
    return src.replace(old,new,1)


def regex_once(src,pattern,repl,label,flags=0):
    out,n=re.subn(pattern,repl,src,count=1,flags=flags)
    if n!=1:
        if repl in src:
            return src
        raise SystemExit(f'{label}: padrão não encontrado')
    return out

HELPERS="""  async function rt82Rpc(name, payload = {}) {
    if (!CLOUD.ready || !CLOUD.session?.access_token || !CLOUD.worldId) throw new Error('Entre no mundo ONLINE para usar esta ação.');
    return cloudRequest(`/rest/v1/rpc/${name}`, { method:'POST', timeoutMs:12000, body:{ p_world_id:CLOUD.worldId, ...payload } });
  }

  async function rt82VillageRpc(name, village, payload = {}, success = 'Ação concluída no servidor.') {
    try {
      if (!village?._cloudVillageId) await ensureAllMultiplayerVillages();
      const villageId=village?._cloudVillageId;
      if (!villageId) throw new Error('Aldeia online ainda não sincronizada.');
      await rt82Rpc(name, { p_village_id:villageId, ...payload });
      await pollMultiplayer(false);
      dirty=true;
      renderAll();
      if (success) toast(success,'success');
      return true;
    } catch (error) {
      CLOUD.lastError=String(error?.message||error);
      toast(CLOUD.lastError,'error');
      return false;
    }
  }

"""

PAYLOAD="""  function cloudVillagePayload(v) {
    return {
      name:v.name,
      clientKey:v._cloudClientKey||v.id,
      ownerName:state?.player?.name || CLOUD.user?.email || 'Governante',
      tribe:state?.player?.tribe || null,
      startProfile: state?.settings?.startProfile || null
    };
  }
"""

PLAYER_SUMMARY="""  async function upsertPlayerSummary() {
    if (!CLOUD.ready || !CLOUD.user?.id || !state) return;
    const p = state.player || {};
    const body = {
      player_name: String(p.name || CLOUD.user.email || 'Governante').slice(0, 64),
      crowns: Math.max(0, Math.floor(Number(p.premium?.crowns) || 0)),
      hero: p.hero || {},
      inventory: p.inventory || {},
      flags_inventory: p.flagsInventory || {},
      premium: p.premium || {},
      last_seen_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };
    const world=encodeURIComponent(CLOUD.worldId), user=encodeURIComponent(CLOUD.user.id);
    await cloudRequest(`/rest/v1/player_worlds?world_id=eq.${world}&user_id=eq.${user}`, {
      method: 'PATCH',
      headers: { Prefer: 'return=minimal' },
      body
    });
  }
"""

for path in HTMLS:
    s=path.read_text(encoding='utf-8')
    s=once(s,"edgePath: '/functions/v1/rt-multiplayer-v60'","edgePath: '/functions/v1/rt-multiplayer-v82'",f'{path.name}: endpoint RT82')
    if 'async function rt82Rpc(' not in s:
        marker='  function cloudVillagePayload(v) {'
        if marker not in s: raise SystemExit(f'{path.name}: cloudVillagePayload ausente')
        s=s.replace(marker,HELPERS+marker,1)
    s=regex_once(s,r"  function cloudVillagePayload\(v\) \{.*?\n  \}\n\n  function ",PAYLOAD+'\n  function ',f'{path.name}: payload metadata-only',re.S)
    s=regex_once(s,r"  async function upsertPlayerSummary\(\) \{.*?\n  \}\n\n  function ",PLAYER_SUMMARY+'\n  function ',f'{path.name}: player summary restrito',re.S)
    s=once(s,"function updateResources(village, timestamp = now()) {\n  if (!village?.resources) return false;","function updateResources(village, timestamp = now()) {\n  if(CLOUD.ready)return false; /* RT82 server progresses online queues */\n  if (!village?.resources) return false;",f'{path.name}: produção online')
    s=once(s,"  function queueBuilding(buildingKey) {\n    const village = getActiveVillage();\n    updateResources(village);","  function queueBuilding(buildingKey) {\n    const village = getActiveVillage();\n    if(CLOUD.ready)return rt82VillageRpc('rt82_queue_building',village,{p_building:buildingKey},'Construção enfileirada no servidor.');\n    updateResources(village);",f'{path.name}: construção')
    s=once(s,"  function cancelBuilding(index) {\n    const village = getActiveVillage();\n    const item = village.buildQueue[index];","  function cancelBuilding(index) {\n    const village = getActiveVillage();\n    if(CLOUD.ready)return rt82VillageRpc('rt82_cancel_building',village,{p_index:Number(index)},'Construção cancelada no servidor.');\n    const item = village.buildQueue[index];",f'{path.name}: cancelar construção')
    s=once(s,"  function queueRecruit(unitKey, quantity) {\n    const v = getActiveVillage(); const def = D.units[unitKey]; const qty = Math.floor(Number(quantity));","  function queueRecruit(unitKey, quantity) {\n    const v = getActiveVillage(); const def = D.units[unitKey]; const qty = Math.floor(Number(quantity));\n    if(CLOUD.ready)return rt82VillageRpc('rt82_queue_recruit',v,{p_unit:unitKey,p_quantity:qty},'Recrutamento enfileirado no servidor.');",f'{path.name}: recrutamento')
    s=once(s,"  function cancelRecruit(index) {\n    const village = getActiveVillage(), item = village.recruitQueue[index];","  function cancelRecruit(index) {\n    const village = getActiveVillage();\n    if(CLOUD.ready)return rt82VillageRpc('rt82_cancel_recruit',village,{p_index:Number(index)},'Recrutamento cancelado no servidor.');\n    const item = village.recruitQueue[index];",f'{path.name}: cancelar recrutamento')
    s=once(s,"  function queueUnitResearch(unitKey) {\n    const v=getActiveVillage(); const current=getUnitResearchLevel(v,unitKey); const target=current+1;","  function queueUnitResearch(unitKey) {\n    const v=getActiveVillage(); const current=getUnitResearchLevel(v,unitKey); const target=current+1;\n    if(CLOUD.ready)return rt82VillageRpc('rt82_queue_unit_research',v,{p_unit:unitKey},'Pesquisa militar enfileirada no servidor.');",f'{path.name}: pesquisa militar')
    s=once(s,"  function queueResearch(researchId) {\n    const v = getActiveVillage();","  function queueResearch(researchId) {\n    const v = getActiveVillage();\n    if(CLOUD.ready)return rt82VillageRpc('rt82_queue_global_research',v,{p_research:researchId},'Pesquisa global enfileirada no servidor.');",f'{path.name}: pesquisa global')
    s=once(s,"  function mintCoin(quantity=1) {\n    const v=getActiveVillage(); const qty=clamp(Math.floor(Number(quantity)||1),1,100);","  function mintCoin(quantity=1) {\n    const v=getActiveVillage(); const qty=clamp(Math.floor(Number(quantity)||1),1,100);\n    if(CLOUD.ready)return rt82VillageRpc('rt82_mint_academy_coins',v,{p_quantity:qty},'Moedas cunhadas pelo servidor.');",f'{path.name}: moedas academia')
    s=once(s,"  function demolishBuilding(buildingKey) {\n    const v=getActiveVillage(), def=D.buildings[buildingKey];","  function demolishBuilding(buildingKey) {\n    const v=getActiveVillage(), def=D.buildings[buildingKey];\n    if(CLOUD.ready)return rt82VillageRpc('rt82_demolish_building',v,{p_building:buildingKey},'Demolição aplicada pelo servidor.');",f'{path.name}: demolição')
    s=once(s,"  function activatePremiumService(serviceId) {\n    const def=PREMIUM_SERVICES[serviceId]; if(!def) return; const p=premiumState();","  async function activatePremiumService(serviceId) {\n    const def=PREMIUM_SERVICES[serviceId]; if(!def) return;\n    if(CLOUD.ready){try{const r=await rt82Rpc('rt82_activate_premium_service',{p_service:serviceId});const p=premiumState();if(r?.premium&&typeof r.premium==='object')state.player.premium={...p,...r.premium};if(r?.crowns!==undefined)state.player.premium.crowns=Math.max(0,Number(r.crowns)||0);if(r?.inventory&&typeof r.inventory==='object')state.player.inventory={...r.inventory};dirty=true;toast(`${def.name} ativado pelo servidor.`,'success');renderAll();return;}catch(e){toast(e.message||String(e),'error');return;}}\n    const p=premiumState();",f'{path.name}: Premium server-side')
    s=once(s,"  function claimPremiumDaily() {\n    const p = premiumState(); const cooldown = 20 * 3600000;","  async function claimPremiumDaily() {\n    if(CLOUD.ready){try{const r=await rt82Rpc('rt82_claim_daily_reward');const p=premiumState();if(r?.premium&&typeof r.premium==='object')state.player.premium={...p,...r.premium};if(r?.crowns!==undefined)state.player.premium.crowns=Math.max(0,Number(r.crowns)||0);if(r?.inventory&&typeof r.inventory==='object')state.player.inventory={...r.inventory};dirty=true;toast('Recompensa diária recebida do servidor.','success');renderAll();return;}catch(e){toast(e.message||String(e),'error');return;}}\n    const p = premiumState(); const cooldown = 20 * 3600000;",f'{path.name}: diária server-side')
    path.write_text(s,encoding='utf-8')

legacy=ROOT/'backend/rt81-multiplayer-safe.ts'
s=legacy.read_text(encoding='utf-8')
pattern=r"async function syncVillage\(u,wid,id,v=\{\}\)\{.*?\}\nfunction publicBuildings"
replacement="""async function syncVillage(u,wid,id,v={}){await access(u.sub,wid);const cur=(await db(`villages?id=eq.${id}&world_id=eq.${wid}&owner_user_id=eq.${u.sub}&select=*&limit=1`))?.[0];if(!cur)throw new Error('Aldeia online inválida.');const b={name:String(v.name||cur.name||'Aldeia').slice(0,80),updated_at:iso()};if(!cur.client_key&&(v.clientKey||v.client_key))b.client_key=String(v.clientKey||v.client_key).slice(0,100);return (await db(`villages?id=eq.${id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:b}))?.[0]}
function publicBuildings"""
if 'const b=sane(v,cur.name)' in s:
    s,n=re.subn(pattern,replacement,s,count=1,flags=re.S)
    if n!=1: raise SystemExit('backend: syncVillage legado não localizado')
legacy.write_text(s,encoding='utf-8')

if HTMLS[0].read_bytes()!=HTMLS[1].read_bytes():
    raise SystemExit('index/JOGAR divergiram após RT82')
print('RT82_CLIENT_AUTHORITY_PATCH_OK')
