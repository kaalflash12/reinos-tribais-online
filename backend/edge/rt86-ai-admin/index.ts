const C={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'content-type,x-admin-token,apikey,authorization',
  'Access-Control-Allow-Methods':'POST,OPTIONS',
  'Content-Type':'application/json; charset=utf-8'
};
const SB=Deno.env.get('SUPABASE_URL')||'', SK=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const out=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:C});
const H=(extra:any={})=>({apikey:SK,Authorization:`Bearer ${SK}`,'Content-Type':'application/json',...extra});
const iso=()=>new Date().toISOString();
const txt=(v:any,n=200)=>String(v??'').slice(0,n);
const num=(v:any,d=0)=>Number.isFinite(Number(v))?Number(v):d;
async function sha(s:string){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('')}
async function db(path:string,o:any={}){
  const r=await fetch(`${SB}/rest/v1/${path}`,{method:o.method||'GET',headers:H(o.headers||{}),body:o.body===undefined?undefined:JSON.stringify(o.body)});
  const t=await r.text();let d:any=null;if(t)try{d=JSON.parse(t)}catch{d=t}
  if(!r.ok)throw Object.assign(new Error(d?.message||d?.hint||d?.details||String(d||r.status)),{status:r.status});
  return d;
}
async function rpc(name:string,body:any){return db(`rpc/${name}`,{method:'POST',body})}
async function auth(req:Request){
  const raw=req.headers.get('x-admin-token')||'';if(!raw)return null;
  const h=await sha(raw);
  const s=(await db(`rt_admin_sessions?token_hash=eq.${h}&expires_at=gt.${encodeURIComponent(iso())}&select=id,admin_id&limit=1`))?.[0];
  if(!s)return null;
  await db(`rt_admin_sessions?id=eq.${s.id}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:{last_seen_at:iso()}}).catch(()=>null);
  return (await db(`rt_admin_accounts?id=eq.${s.admin_id}&active=eq.true&select=id,username,role,display_name&limit=1`))?.[0]||null;
}
async function audit(a:any,action:string,wid:any,payload:any={}){
  await db('rt_admin_audit_log',{method:'POST',headers:{Prefer:'return=minimal'},body:{admin_id:a.id,action,world_id:wid||null,payload}}).catch(()=>null);
}
const personalities=['raider','warden','merchant','scholar','opportunist','conqueror','diplomat','builder'];
async function oneStatus(wid:string){
  const status=await rpc('rt86_ai_public_status',{p_world_id:wid});
  const balances=await db(`rt86_monster_balance?world_id=eq.${encodeURIComponent(wid)}&select=monster_id,base_level,base_hp,balanced_level,balanced_hp,player_median_points,balanced_at&order=balanced_at.desc&limit=100`).catch(()=>[]);
  const counts={
    ai_villages:(await db(`villages?world_id=eq.${encodeURIComponent(wid)}&owner_kind=eq.ai&select=id`)).length,
    barbarian_villages:(await db(`villages?world_id=eq.${encodeURIComponent(wid)}&owner_kind=eq.barbarian&select=id`)).length,
    active_monsters:(await db(`world_monsters?world_id=eq.${encodeURIComponent(wid)}&status=eq.active&select=id`)).length,
    active_events:(await db(`rt_world_events?world_id=eq.${encodeURIComponent(wid)}&status=eq.active&select=id`)).length
  };
  return {...(status||{}),world_id:wid,counts,monster_balance:balances};
}
async function action(a:any,act:string,b:any){
  if(act==='status'){
    if(b.world_id)return oneStatus(String(b.world_id));
    const worlds=await db('worlds?is_active=eq.true&select=id,name,slug,status&order=created_at');
    const outx=[];for(const w of worlds)outx.push({world:w,status:await oneStatus(w.id)});return {version:86,worlds:outx};
  }
  if(act==='tick'){
    const wid=String(b.world_id||'');if(!wid)throw new Error('world_id obrigatório.');
    const result=await rpc('rt86_ai_director_tick',{p_world_id:wid});await audit(a,'rt86_ai_manual_tick',wid,{result});return {ok:true,result};
  }
  if(act==='config'){
    const wid=String(b.world_id||'');if(!wid)throw new Error('world_id obrigatório.');
    const patch:any={updated_at:iso()};
    if(b.enabled!==undefined)patch.enabled=Boolean(b.enabled);
    if(b.mode!==undefined)patch.mode=txt(b.mode,32);
    if(b.target_difficulty!==undefined)patch.target_difficulty=Math.max(.65,Math.min(1.5,num(b.target_difficulty,1)));
    if(b.event_pressure!==undefined)patch.event_pressure=Math.max(1,Math.min(10,Math.floor(num(b.event_pressure,5))));
    if(b.monster_pressure!==undefined)patch.monster_pressure=Math.max(1,Math.min(10,Math.floor(num(b.monster_pressure,5))));
    patch.next_tick=iso();
    await db(`rt86_ai_director_state?world_id=eq.${encodeURIComponent(wid)}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:patch});
    await audit(a,'rt86_ai_config',wid,{patch});return {ok:true,status:await oneStatus(wid)};
  }
  if(act==='agent_patch'){
    const id=String(b.agent_id||'');if(!id)throw new Error('agent_id obrigatório.');
    const old=(await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}&select=id,world_id,display_name,personality,enabled,traits,goals&limit=1`))?.[0];if(!old)throw new Error('Agente NPC não encontrado.');
    const patch:any={updated_at:iso(),next_tick:iso()};
    if(b.enabled!==undefined)patch.enabled=Boolean(b.enabled);
    if(b.personality!==undefined){const p=String(b.personality);if(!personalities.includes(p))throw new Error('Personalidade inválida.');patch.personality=p}
    if(b.traits&&typeof b.traits==='object')patch.traits={...(old.traits||{}),...b.traits};
    if(b.goals&&typeof b.goals==='object')patch.goals={...(old.goals||{}),...b.goals};
    await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:patch});
    await audit(a,'rt86_ai_agent_patch',old.world_id,{agent_id:id,npc:old.display_name,patch});return {ok:true,agent:(await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}&select=*&limit=1`))?.[0]};
  }
  if(act==='agent_tick'){
    const id=String(b.agent_id||'');const ag=(await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}&select=id,world_id,display_name&limit=1`))?.[0];if(!ag)throw new Error('Agente NPC não encontrado.');
    await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:{next_tick:iso(),updated_at:iso()}});
    const result=await rpc('rt86_ai_agents_tick',{p_world_id:ag.world_id,p_limit:60});await audit(a,'rt86_ai_agent_tick',ag.world_id,{agent_id:id,npc:ag.display_name,result});return {ok:true,result};
  }
  if(act==='reset_memory'){
    const id=String(b.agent_id||'');const ag=(await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}&select=id,world_id,display_name&limit=1`))?.[0];if(!ag)throw new Error('Agente NPC não encontrado.');
    await db(`rt86_npc_ai_agents?id=eq.${encodeURIComponent(id)}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:{memory:{known_targets:{},recent_losses:0,recent_wins:0,last_enemy:null},updated_at:iso()}});
    await audit(a,'rt86_ai_agent_memory_reset',ag.world_id,{agent_id:id,npc:ag.display_name});return {ok:true};
  }
  throw new Error('Ação RT86 desconhecida.');
}
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  if(req.method!=='POST')return out({error:'Método inválido.'},405);
  try{const b=await req.json().catch(()=>({}));const a=await auth(req);if(!a)return out({error:'Sessão administrativa inválida ou expirada.'},401);return out(await action(a,String(b.action||'status'),b));}
  catch(e:any){console.error('rt86-ai-admin',e);return out({error:e?.message||String(e)},e?.status||400)}
});
