from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
HTMLS=[ROOT/'index.html',ROOT/'JOGAR_REINOS_TRIBAIS.html']

def once(s,old,new,label):
    if new in s:return s
    n=s.count(old)
    if n!=1:raise SystemExit(f'{label}: esperado 1, encontrado {n}')
    return s.replace(old,new,1)

for p in HTMLS:
    s=p.read_text(encoding='utf-8')
    s=s.replace("      flags_inventory: p.flagsInventory || {},\n",'')
    s=once(s,"  function assignFlag(flagKey) {\n    const inv=ensureFlagsInventory(), v=getActiveVillage(); const [type,lvlRaw]=flagKey.split('_');","  async function assignFlag(flagKey) {\n    const inv=ensureFlagsInventory(), v=getActiveVillage();\n    if(CLOUD.ready){try{if(!v._cloudVillageId)await ensureAllMultiplayerVillages();if(!v._cloudVillageId)throw new Error('Aldeia online ainda não sincronizada.');const r=await rt82Rpc('rt82_assign_flag',{p_village_id:v._cloudVillageId,p_flag_key:flagKey});if(r?.flags_inventory)state.player.flagsInventory={...r.flags_inventory};if(r?.flag)v.flag={...r.flag};await pollMultiplayer(false);dirty=true;toast('Bandeira hasteada pelo servidor.','success');renderAll();return;}catch(e){toast(e.message||String(e),'error');return;}}\n    const [type,lvlRaw]=flagKey.split('_');",f'{p.name}: assign flag')
    s=once(s,"  function removeFlag() {\n    const v=getActiveVillage(); if(!v.flag)return;","  async function removeFlag() {\n    const v=getActiveVillage();\n    if(CLOUD.ready){try{if(!v._cloudVillageId)await ensureAllMultiplayerVillages();if(!v._cloudVillageId)throw new Error('Aldeia online ainda não sincronizada.');const r=await rt82Rpc('rt82_remove_flag',{p_village_id:v._cloudVillageId});if(r?.flags_inventory)state.player.flagsInventory={...r.flags_inventory};v.flag=null;await pollMultiplayer(false);dirty=true;toast('Bandeira retirada pelo servidor.','success');renderAll();return;}catch(e){toast(e.message||String(e),'error');return;}}\n    if(!v.flag)return;",f'{p.name}: remove flag')
    s=once(s,"  function combineFlags(flagKey) {\n    const inv=ensureFlagsInventory(); const [type,lvlRaw]=flagKey.split('_');","  async function combineFlags(flagKey) {\n    const inv=ensureFlagsInventory();\n    if(CLOUD.ready){try{const r=await rt82Rpc('rt82_combine_flags',{p_flag_key:flagKey});if(r?.flags_inventory)state.player.flagsInventory={...r.flags_inventory};dirty=true;toast(`Bandeiras combinadas: ${r?.created||'novo nível'}.`,'success');renderAll();return;}catch(e){toast(e.message||String(e),'error');return;}}\n    const [type,lvlRaw]=flagKey.split('_');",f'{p.name}: combine flags')
    p.write_text(s,encoding='utf-8')

if HTMLS[0].read_bytes()!=HTMLS[1].read_bytes():raise SystemExit('index/JOGAR divergiram')
print('RT82_FLAGS_AUTHORITY_PATCH_OK')
