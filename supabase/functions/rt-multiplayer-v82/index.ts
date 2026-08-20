const C={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
  'Content-Type':'application/json; charset=utf-8'
};
const SB=Deno.env.get('SUPABASE_URL')||'',SK=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const out=(x,s=200)=>new Response(JSON.stringify(x),{status:s,headers:C});
const num=v=>Math.max(0,Math.floor(Number(v)||0));
const clamp=(v,a,b)=>Math.max(a,Math.min(b,Number(v)||a));
const iso=()=>new Date().toISOString();
const nowms=()=>Date.now();

function user(req){
  const a=req.headers.get('authorization')||'',t=a.replace(/^Bearer\s+/i,''),p=t.split('.')[1]||'';
  if(!p)return null;
  try{return JSON.parse(atob(p.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(p.length/4)*4,'=')))}catch{return null}
}
async function db(path,o={}){
  const r=await fetch(`${SB}/rest/v1/${path}`,{
    method:o.method||'GET',
    headers:{apikey:SK,Authorization:`Bearer ${SK}`,'Content-Type':'application/json',...(o.headers||{})},
    body:o.body===undefined?undefined:JSON.stringify(o.body)
  });
  const t=await r.text();let d=null;if(t)try{d=JSON.parse(t)}catch{d=t}
  if(!r.ok)throw new Error(d?.message||d?.hint||String(d||r.status));
  return d;
}
async function rpcAsUser(req,name,body){
  const auth=req.headers.get('authorization')||'';
  const r=await fetch(`${SB}/rest/v1/rpc/${name}`,{
    method:'POST',
    headers:{apikey:SK,Authorization:auth,'Content-Type':'application/json'},
    body:JSON.stringify(body||{})
  });
  const t=await r.text();let d=null;if(t)try{d=JSON.parse(t)}catch{d=t}
  if(!r.ok)throw new Error(d?.message||d?.hint||String(d||r.status));
  return d;
}
function hash(s=''){let h=2166136261>>>0;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)>>>0}return h>>>0}
function cleanName(v,fallback='Aldeia'){return String(v||fallback).trim().slice(0,80)||fallback}

const BASE_BUILDINGS={main:3,barracks:1,stable:0,workshop:0,church:0,first_church:0,academy:0,smith:0,rally:1,statue:0,market:1,timber:4,clay:4,iron:3,farm:4,warehouse:4,hide:1,wall:1,watchtower:0,garage:0};
const BASE_UNITS={spear:30,sword:10,axe:0,archer:0,spy:0,light:0,marcher:0,heavy:0,ram:0,catapult:0,paladin:0,noble:0,militia:0};
const BASE_RESEARCH={spear:1,sword:1,axe:0,archer:0,spy:0,light:0,marcher:0,heavy:0,ram:0,catapult:0};
function clone(o){return JSON.parse(JSON.stringify(o))}
function profileFromIntent(v={}){
  const explicit=String(v.startProfile||v.start_profile||'').toLowerCase();
  if(['balanced','economy','military'].includes(explicit))return explicit;
  const b=v.buildings||{},u=v.units||{},r=v.unitResearch||v.unit_research||{};
  if(num(b.main)>=5&&num(b.barracks)>=5&&num(b.smith)>=2&&num(u.axe)>=15&&num(r.axe)>=1)return 'military';
  if(num(b.timber)>=5&&num(b.clay)>=5&&num(b.iron)>=4&&num(b.farm)>=5&&num(b.warehouse)>=5)return 'economy';
  return 'balanced';
}
function villagePoints(buildings){
  let points=0;
  for(const [key,raw] of Object.entries(buildings||{})){
    const level=num(raw),weight=['main','academy','smith'].includes(key)?12:['timber','clay','iron'].includes(key)?7:9;
    points+=Math.floor(weight*Math.pow(level,1.38));
  }
  return Math.max(26,Math.floor(points));
}
function canonicalSpawn(v={}){
  const profile=profileFromIntent(v),buildings=clone(BASE_BUILDINGS),units=clone(BASE_UNITS),unit_research=clone(BASE_RESEARCH);
  let resources={wood:1200,clay:1200,iron:1000,lastUpdate:nowms()};
  if(profile==='economy'){
    buildings.timber+=1;buildings.clay+=1;buildings.iron+=1;buildings.farm+=1;buildings.warehouse+=1;
    resources={wood:1800,clay:1800,iron:1500,lastUpdate:nowms()};
  }else if(profile==='military'){
    buildings.main=Math.max(buildings.main,5);buildings.barracks=Math.max(buildings.barracks,5);buildings.smith=Math.max(buildings.smith,2);
    units.spear+=30;units.sword+=20;units.axe+=15;unit_research.axe=1;
    resources={wood:1500,clay:1300,iron:1200,lastUpdate:nowms()};
  }
  return {
    profile,
    name:cleanName(v.name,'Aldeia'),
    points:villagePoints(buildings),loyalty:100,
    buildings,units,resources,
    build_queue:[],recruit_queue:[],supports:[],unit_research,unit_research_queue:[],
    scavenging:{unlocked:['humble'],active:{}},flag:null,militia_called:false,updated_at:iso()
  };
}

async function access(uid,wid){
  const [w,p,a]=await Promise.all([
    db(`worlds?id=eq.${encodeURIComponent(wid)}&select=id,is_active,status,settings&limit=1`),
    db(`player_worlds?world_id=eq.${encodeURIComponent(wid)}&user_id=eq.${encodeURIComponent(uid)}&select=id,is_suspended,player_name&limit=1`),
    db(`rt_admin_auth_users?user_id=eq.${encodeURIComponent(uid)}&active=eq.true&select=user_id&limit=1`)
  ]);
  if(a?.length)throw new Error('Conta administrativa não pode jogar.');
  if(!w?.[0]||!w[0].is_active||String(w[0].status||'open')!=='open')throw new Error('Mundo fechado.');
  if(!p?.length||p[0].is_suspended)throw new Error('Entre no mundo antes de jogar.');
  return {world:w[0],player:p[0]};
}
async function allocateCoord(uid,wid,ck,w){
  const rad=clamp(w?.settings?.mapRadius||35,12,80),side=rad*2+1;
  const [vr,nr]=await Promise.all([
    db(`villages?world_id=eq.${encodeURIComponent(wid)}&select=x,y`),
    db(`world_nodes?world_id=eq.${encodeURIComponent(wid)}&select=x,y`).catch(()=>[])
  ]);
  const occ=new Set([...(vr||[]),...(nr||[])].map(x=>`${x.x}|${x.y}`));
  const start=hash(`${uid}|${ck||''}`)%(side*side);
  for(let i=0;i<side*side;i++){
    const q=(start+i*37)%(side*side),x=500-rad+(q%side),y=500-rad+Math.floor(q/side);
    if(x>=0&&x<=999&&y>=0&&y<=999&&!occ.has(`${x}|${y}`))return {x,y};
  }
  throw new Error('Sem coordenadas livres.');
}
async function ensureVillage(u,wid,v={}){
  const {world,player}=await access(u.sub,wid),ck=String(v.clientKey||v.client_key||'').slice(0,100)||null;
  const own=await db(`villages?world_id=eq.${encodeURIComponent(wid)}&owner_user_id=eq.${encodeURIComponent(u.sub)}&select=*&order=updated_at.asc`);
  if(ck){const hit=(own||[]).find(x=>x.client_key===ck);if(hit)return hit}
  if((own||[]).length===1&&!own[0].client_key&&ck){
    const row=(await db(`villages?id=eq.${own[0].id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:{client_key:ck,updated_at:iso()}}))?.[0];
    return row||own[0];
  }
  if((own||[]).length>0)throw new Error('Criação adicional de aldeia não é permitida; conquistas são registradas pelo servidor.');
  const pos=await allocateCoord(u.sub,wid,ck,world),spawn=canonicalSpawn(v);
  const row={
    world_id:wid,owner_user_id:u.sub,owner_kind:'player',owner_name:cleanName(player?.player_name||u.email||'Governante','Governante'),
    tribe_name:null,x:pos.x,y:pos.y,client_key:ck,...spawn
  };
  try{return (await db('villages',{method:'POST',headers:{Prefer:'return=representation'},body:row}))?.[0]}
  catch(e){
    if(!String(e?.message||e).toLowerCase().includes('duplicate'))throw e;
    const retry=await allocateCoord(u.sub,wid,`${ck||''}|retry`,world);
    row.x=retry.x;row.y=retry.y;
    return (await db('villages',{method:'POST',headers:{Prefer:'return=representation'},body:row}))?.[0];
  }
}
async function progressOwn(req,wid){
  await rpcAsUser(req,'rt82_progress_state',{p_world_id:wid});
  await rpcAsUser(req,'rt82_produce_resources',{p_world_id:wid});
}
async function syncVillage(req,u,wid,id,v={}){
  await access(u.sub,wid);
  const cur=(await db(`villages?id=eq.${encodeURIComponent(id)}&world_id=eq.${encodeURIComponent(wid)}&owner_user_id=eq.${encodeURIComponent(u.sub)}&select=*&limit=1`))?.[0];
  if(!cur)throw new Error('Aldeia online inválida.');
  const patch={name:cleanName(v.name,cur.name),updated_at:iso()};
  if(!cur.client_key&&(v.clientKey||v.client_key))patch.client_key=String(v.clientKey||v.client_key).slice(0,100);
  await db(`villages?id=eq.${encodeURIComponent(id)}`,{method:'PATCH',headers:{Prefer:'return=minimal'},body:patch});
  await progressOwn(req,wid);
  return (await db(`villages?id=eq.${encodeURIComponent(id)}&world_id=eq.${encodeURIComponent(wid)}&owner_user_id=eq.${encodeURIComponent(u.sub)}&select=*&limit=1`))?.[0];
}
function publicBuildings(points){const p=num(points),s=p<300?1:p<700?3:p<1500?5:p<3500?8:p<8000?11:p<16000?14:p<32000?18:22,z=(d,min=0)=>Math.max(min,Math.min(30,s-d));return {main:s,barracks:z(1,1),stable:z(4),garage:z(7),smith:z(3),rally:1,market:z(3),timber:z(1,1),clay:z(1,1),iron:z(1,1),farm:z(1,1),warehouse:z(2,1),hide:z(8),wall:z(5),academy:z(9),statue:s>=5?1:0,watchtower:z(10),church:0,first_church:0}}
function publicVillage(v){return {id:v.id,owner_user_id:v.owner_user_id,owner_kind:v.owner_kind,owner_name:v.owner_name,tribe_name:v.tribe_name,name:v.name,x:v.x,y:v.y,points:num(v.points),buildings:publicBuildings(v.points),updated_at:v.updated_at,public_visual_projection:true}}
function incoming(target,c){
  const lvl=num(target?.buildings?.watchtower),real=c.troops&&typeof c.troops==='object'?c.troops:{},total=Object.values(real).reduce((a,b)=>a+num(b),0),noble=num(real.noble)>0,siege=num(real.ram)+num(real.catapult)>0,spy=num(real.spy)>0;
  let troops={},visible=null,visibility='unknown',klass='unknown',approx=false;
  if(lvl>=1&&lvl<5){visible=Math.max(1,Math.round(total/25)*25);troops={spear:visible};visibility='approximate';klass='hostile';approx=true}
  else if(lvl>=5&&lvl<10){visible=total;troops={spear:total};visibility='quantity';klass='attack'}
  else if(lvl>=10&&lvl<15){visible=total;const f=(noble?1:0)+(siege?1:0);troops={spear:Math.max(0,total-f)};if(siege)troops.ram=1;if(noble)troops.noble=1;visibility='tactical';klass=noble?'noble':siege?'siege':spy&&total<=num(real.spy)+2?'spy':total<=10?'fake_likely':'attack'}
  else if(lvl>=15){visible=total;troops=real;visibility='composition';klass=noble?'noble':siege?'siege':spy&&total<=num(real.spy)+2?'spy':total<=10?'fake_likely':'attack'}
  const urgency=new Date(c.arrives_at).getTime()<Date.now()+600000?20:0,risk=Math.min(100,Math.max(1,20+urgency+(visible==null?0:Math.min(50,visible/20))+(lvl>=10&&noble?25:0)+(lvl>=10&&siege?15:0)));
  return {...c,troops,payload:lvl>=15?(c.payload||{}):{travel_ms:num(c.payload?.travel_ms)},rt81_intel:{watchtower_level:lvl,visibility,total_units:visible,approximate:approx,class:klass,siege_detected:lvl>=10?siege:null,noble_detected:lvl>=10?noble:null,risk:Math.round(risk)}};
}
async function poll(req,u,wid){
  await access(u.sub,wid);await progressOwn(req,wid);
  const own=await db(`villages?world_id=eq.${encodeURIComponent(wid)}&owner_user_id=eq.${encodeURIComponent(u.sub)}&select=*`),world=await db(`villages?world_id=eq.${encodeURIComponent(wid)}&select=id,owner_user_id,owner_kind,owner_name,tribe_name,name,x,y,points,updated_at&order=points.desc&limit=2000`),ids=(own||[]).map(v=>v.id),ownMap=new Map((own||[]).map(v=>[String(v.id),v]));
  let commands=[];
  if(ids.length)commands=await db(`commands?world_id=eq.${encodeURIComponent(wid)}&or=(owner_user_id.eq.${encodeURIComponent(u.sub)},target_village_id.in.(${ids.join(',')}))&select=*&order=started_at.desc&limit=80`);
  commands=(commands||[]).map(c=>String(c.owner_user_id)===u.sub?c:ownMap.has(String(c.target_village_id))?incoming(ownMap.get(String(c.target_village_id)),c):null).filter(Boolean);
  const reports=await db(`reports?world_id=eq.${encodeURIComponent(wid)}&user_id=eq.${encodeURIComponent(u.sub)}&select=*&order=created_at.desc&limit=30`);
  return {version:82,security_revision:'rt82.preview1',own_villages:own||[],world_villages:(world||[]).map(publicVillage),commands,reports:reports||[]};
}
async function callLegacy(req,body){
  const r=await fetch(`${SB}/functions/v1/rt-multiplayer-v59`,{method:'POST',headers:{apikey:req.headers.get('apikey')||'',Authorization:req.headers.get('authorization')||'','Content-Type':'application/json'},body:JSON.stringify(body)}),text=await r.text();let data=null;try{data=text?JSON.parse(text):null}catch{data=text}
  if(!r.ok)throw new Error(data?.error||data?.message||String(data||r.status));return data;
}
async function resolveLegacyDue(req,body){return callLegacy(req,{...body,action:'poll',rt81_due_pass:true})}
async function proxyAttack(req,body){return out(await callLegacy(req,body))}

Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  if(req.method!=='POST')return out({error:'Método inválido.'},405);
  const u=user(req);if(!u?.sub)return out({error:'Sessão inválida.'},401);
  try{
    const body=await req.json(),wid=String(body.world_id||''),action=String(body.action||'');
    if(!wid)throw new Error('world_id ausente.');
    if(action==='poll'){if(!body.rt81_due_pass)await resolveLegacyDue(req,body);return out(await poll(req,u,wid))}
    if(action==='ensure_village')return out({village:await ensureVillage(u,wid,body.village||{})});
    if(action==='sync_village')return out({village:await syncVillage(req,u,wid,String(body.village_id||''),body.village||{})});
    if(action==='send_attack')return await proxyAttack(req,body);
    return out({error:'Ação desconhecida.'},400);
  }catch(e){console.error(e);return out({error:e?.message||String(e)},400)}
});
