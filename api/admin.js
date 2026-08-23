import { connect } from '@tursodatabase/serverless';
import { createHash, randomBytes, randomUUID, scryptSync } from 'node:crypto';

let connection;
const DEFAULT_WORLD_ID='d5a546fb-316d-4332-ae92-1886d80b07df';
const now=()=>new Date().toISOString();
const hashToken=v=>createHash('sha256').update(String(v||'')).digest('hex');
const passwordHash=(password,salt=randomBytes(16).toString('hex'))=>`scrypt$${salt}$${scryptSync(String(password),salt,64).toString('hex')}`;
const parse=(v,f={})=>{try{return v?JSON.parse(v):f}catch{return f}};
const db=()=>connection||(connection=connect({url:process.env.TURSO_DATABASE_URL,authToken:process.env.TURSO_AUTH_TOKEN}));

function cors(req,res){
  const origin=String(req.headers.origin||'');
  const allowed=new Set(['https://kaalflash12.github.io','http://localhost:3000','http://127.0.0.1:3000']);
  if(!origin||allowed.has(origin)||/^https:\/\/[a-z0-9-]+\.vercel\.app$/i.test(origin))res.setHeader('Access-Control-Allow-Origin',origin||'*');
  res.setHeader('Vary','Origin');res.setHeader('Access-Control-Allow-Headers','authorization,content-type,x-admin-token');res.setHeader('Access-Control-Allow-Methods','POST,OPTIONS');res.setHeader('Cache-Control','no-store');
}
function token(req){const a=String(req.headers.authorization||'');if(a.toLowerCase().startsWith('bearer '))return a.slice(7).trim();return String(req.headers['x-admin-token']||'').trim()}
async function admin(req){
  const raw=token(req);if(!raw)throw Object.assign(new Error('Sessão administrativa necessária.'),{status:401});
  const row=await db().prepare(`SELECT u.*,s.token_hash,s.expires_at FROM rt_sessions s JOIN rt_users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? LIMIT 1`).get([hashToken(raw),now()]);
  if(!row||row.role!=='admin'||row.disabled)throw Object.assign(new Error('Sessão administrativa inválida.'),{status:401});
  return {raw,user:row};
}
async function audit(user,action,target='',payload={}){await db().prepare('INSERT INTO rt_admin_audit(id,admin_user_id,action,target,payload_json,created_at) VALUES (?,?,?,?,?,?)').run([randomUUID(),user.id,action,String(target||''),JSON.stringify(payload||{}),now()])}

async function dashboard(a){
  const worldsRaw=await db().prepare('SELECT * FROM rt_worlds ORDER BY created_at ASC').all([]);
  const worlds=worldsRaw.map(w=>{const s=parse(w.settings_json,{});return {...w,is_active:Boolean(w.is_active),settings:s,worldSpeed:Number(s.worldSpeed||1),unitSpeed:Number(s.unitSpeed||1),mapRadius:Number(s.mapRadius||35),resourceMultiplier:Number(s.resourceMultiplier||1),marketMultiplier:Number(s.marketMultiplier||1)}});
  const rows=await db().prepare(`SELECT pw.*,u.email,u.username,u.role,u.disabled,u.created_at AS account_created_at,u.last_login_at FROM rt_player_worlds pw JOIN rt_users u ON u.id=pw.user_id ORDER BY pw.last_seen_at DESC`).all([]);
  const players=rows.map(r=>({...parse(r.summary_json,{}),world_id:r.world_id,user_id:r.user_id,player_name:r.player_name||r.username,email:r.email,username:r.username,role:r.role,is_suspended:Boolean(r.disabled),joined_at:r.joined_at,last_seen_at:r.last_seen_at,updated_at:r.updated_at,account_created_at:r.account_created_at,last_login_at:r.last_login_at}));
  const admins=await db().prepare(`SELECT id,username,email,role,disabled,created_at,last_login_at FROM rt_users WHERE role='admin' ORDER BY created_at`).all([]);
  const sessions=await db().prepare(`SELECT s.token_hash AS id,s.user_id,s.created_at,s.last_seen_at,s.expires_at,u.username FROM rt_sessions s JOIN rt_users u ON u.id=s.user_id WHERE u.role='admin' AND s.expires_at>? ORDER BY s.created_at DESC`).all([now()]);
  const counts=await db().prepare(`SELECT (SELECT COUNT(*) FROM rt_users) users,(SELECT COUNT(*) FROM rt_player_worlds) player_worlds,(SELECT COUNT(*) FROM rt_game_saves) saves,(SELECT COUNT(*) FROM rt_documents) documents`).get([]);
  await audit(a.user,'dashboard');
  return {worlds,players,villages:[],nodes:[],events:[],monsters:[],eventTemplates:[],monsterTemplates:[],commands:[],attacks:[],tribes:[],tribeMembers:[],offers:[],messages:[],reports:[],entitlements:[],rtWorldEvents:[],eventProgress:[],eventRewards:[],auditLog:[],seasons:[],ratings:[],matches:[],monsterHits:[],worldStats:[],adminSessions:sessions,adminAccounts:admins,dbCounts:counts};
}
async function worldCreate(a,b){const id=randomUUID(),t=now(),speed=Math.max(.1,Number(b.speed||1)),radius=Math.max(10,Number(b.mapRadius||35)),slug=`mundo-${Date.now().toString(36)}`;const settings={worldSpeed:speed,unitSpeed:speed,mapRadius:radius,resourceMultiplier:1,marketMultiplier:1};await db().prepare(`INSERT INTO rt_worlds(id,name,slug,status,is_active,season_number,max_players,settings_json,opened_at,created_at,updated_at) VALUES (?,?,?,'open',1,1,5000,?,?,?,?)`).run([id,String(b.name||'Novo Mundo').slice(0,80),slug,JSON.stringify(settings),t,t,t]);await audit(a.user,'world_create',id,b);return {ok:true,id}}
async function worldPatch(a,b){const id=String(b.world_id||DEFAULT_WORLD_ID);const row=await db().prepare('SELECT * FROM rt_worlds WHERE id=?').get([id]);if(!row)throw Object.assign(new Error('Mundo não encontrado.'),{status:404});const s={...parse(row.settings_json,{})};for(const k of ['worldSpeed','unitSpeed','mapRadius','resourceMultiplier','marketMultiplier'])if(b[k]!=null)s[k]=Number(b[k]);for(const k of ['archers','militia','church','watchtower','flags','scavenging','eventSystem','monstersEnabled'])if(b[k]!=null)s[k]=Boolean(b[k]);const status=String(b.status||row.status),max=Math.max(1,Number(b.max_players||row.max_players)),season=Math.max(1,Number(b.season_number||row.season_number));await db().prepare('UPDATE rt_worlds SET status=?,max_players=?,season_number=?,settings_json=?,updated_at=? WHERE id=?').run([status,max,season,JSON.stringify(s),now(),id]);await audit(a.user,'world_patch',id,b);return {ok:true}}
async function playerSaveGet(a,b){const row=await db().prepare('SELECT state_json,updated_at,state_version FROM rt_game_saves WHERE world_id=? AND user_id=?').get([String(b.world_id||DEFAULT_WORLD_ID),String(b.user_id||'')]);await audit(a.user,'player_save_get',b.user_id,{world_id:b.world_id});return {save:row?{state:parse(row.state_json,{}),updated_at:row.updated_at,state_version:Number(row.state_version||1)}:null}}
async function playerSaveSet(a,b){const world=String(b.world_id||DEFAULT_WORLD_ID),uid=String(b.user_id||''),state=JSON.stringify(b.state??{}),t=now();await db().prepare(`INSERT INTO rt_game_saves(world_id,user_id,state_json,state_version,created_at,updated_at) VALUES (?,?,?,1,?,?) ON CONFLICT(world_id,user_id) DO UPDATE SET state_json=excluded.state_json,state_version=rt_game_saves.state_version+1,updated_at=excluded.updated_at`).run([world,uid,state,t,t]);await audit(a.user,'player_save_set',uid,{world_id:world});return {ok:true}}
async function playerResetSave(a,b){await db().prepare('DELETE FROM rt_game_saves WHERE world_id=? AND user_id=?').run([String(b.world_id||DEFAULT_WORLD_ID),String(b.user_id||'')]);await audit(a.user,'player_reset_save',b.user_id,{world_id:b.world_id});return {ok:true}}
async function revokeUser(a,b){const uid=String(b.user_id||'');await db().prepare('DELETE FROM rt_sessions WHERE user_id=?').run([uid]);await audit(a.user,'player_revoke_sessions',uid);return {ok:true}}
async function setUserPassword(a,b){const uid=String(b.user_id||''),p=String(b.password||'');if(p.length<8)throw Object.assign(new Error('Senha precisa ter ao menos 8 caracteres.'),{status:400});await db().prepare('UPDATE rt_users SET password_hash=?,updated_at=? WHERE id=?').run([passwordHash(p),now(),uid]);await db().prepare('DELETE FROM rt_sessions WHERE user_id=?').run([uid]);await audit(a.user,'player_set_password',uid);return {ok:true}}
async function changePassword(a,b){const p=String(b.password||'');if(p.length<12)throw Object.assign(new Error('Senha administrativa precisa ter ao menos 12 caracteres.'),{status:400});await db().prepare('UPDATE rt_users SET password_hash=?,updated_at=? WHERE id=?').run([passwordHash(p),now(),a.user.id]);await db().prepare('DELETE FROM rt_sessions WHERE user_id=?').run([a.user.id]);await audit(a.user,'change_password',a.user.id);return {ok:true}}
async function playerPatch(a,b){const world=String(b.world_id||DEFAULT_WORLD_ID),uid=String(b.user_id||''),row=await db().prepare('SELECT * FROM rt_player_worlds WHERE world_id=? AND user_id=?').get([world,uid]);if(!row)throw Object.assign(new Error('Jogador não está neste mundo.'),{status:404});const s={...parse(row.summary_json,{})};const reserved=new Set(['action','world_id','user_id']);for(const [k,v] of Object.entries(b))if(!reserved.has(k)&&v!==undefined)s[k]=v;const name=String(b.player_name||row.player_name).slice(0,32);await db().prepare('UPDATE rt_player_worlds SET player_name=?,summary_json=?,updated_at=?,last_seen_at=? WHERE world_id=? AND user_id=?').run([name,JSON.stringify(s),now(),now(),world,uid]);if(b.is_suspended!=null)await db().prepare('UPDATE rt_users SET disabled=?,updated_at=? WHERE id=?').run([b.is_suspended?1:0,now(),uid]);await audit(a.user,'player_patch',uid,{world_id:world});return {ok:true}}

export default async function handler(req,res){
  cors(req,res);if(req.method==='OPTIONS')return res.status(204).end();if(req.method!=='POST')return res.status(405).json({error:'Método inválido.'});
  try{
    if(!process.env.TURSO_DATABASE_URL||!process.env.TURSO_AUTH_TOKEN)throw Object.assign(new Error('Turso não configurado.'),{status:503});
    const b=typeof req.body==='object'?(req.body||{}):JSON.parse(req.body||'{}');const a=await admin(req);const action=String(b.action||'');
    if(action==='dashboard')return res.json(await dashboard(a));
    if(action==='player_save_get')return res.json(await playerSaveGet(a,b));
    if(action==='player_save_set')return res.json(await playerSaveSet(a,b));
    if(action==='player_reset_save')return res.json(await playerResetSave(a,b));
    if(action==='player_revoke_sessions')return res.json(await revokeUser(a,b));
    if(action==='player_set_password')return res.json(await setUserPassword(a,b));
    if(action==='change_password')return res.json(await changePassword(a,b));
    if(action==='world_create')return res.json(await worldCreate(a,b));
    if(action==='world_patch')return res.json(await worldPatch(a,b));
    if(action==='world_toggle'){await db().prepare('UPDATE rt_worlds SET is_active=?,updated_at=? WHERE id=?').run([b.is_active?1:0,now(),String(b.world_id||'')]);await audit(a.user,'world_toggle',b.world_id,{is_active:Boolean(b.is_active)});return res.json({ok:true})}
    if(action==='player_patch'||action==='player_patch_full'||action==='player_control_patch')return res.json(await playerPatch(a,b));
    if(action==='logout'){await db().prepare('DELETE FROM rt_sessions WHERE token_hash=?').run([hashToken(a.raw)]);return res.json({ok:true})}
    throw Object.assign(new Error('Ação administrativa ainda não migrada para Turso.'),{status:400});
  }catch(e){console.error('reino-admin-api',e);return res.status(Number(e?.status||500)).json({error:Number(e?.status||500)>=500?'Falha temporária do servidor administrativo.':String(e?.message||e)})}
}
