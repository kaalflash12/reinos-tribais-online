const H={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
  'Content-Type':'application/json; charset=utf-8'
};
const URL=Deno.env.get('SUPABASE_URL')||'';
const SERVICE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const ANON=Deno.env.get('SUPABASE_ANON_KEY')||'';
const out=(data:any,status=200)=>new Response(JSON.stringify(data),{status,headers:H});
const normalize=(v:any)=>String(v||'').trim().toLowerCase().replace(/[^a-z0-9_.-]+/g,'_').replace(/^_+|_+$/g,'').slice(0,32);
const serviceHeaders=(extra:any={})=>({apikey:SERVICE,Authorization:`Bearer ${SERVICE}`,'Content-Type':'application/json',...extra});
async function db(path:string,opt:any={}){
  const r=await fetch(`${URL}/rest/v1/${path}`,{method:opt.method||'GET',headers:serviceHeaders(opt.headers||{}),body:opt.body===undefined?undefined:JSON.stringify(opt.body)});
  const t=await r.text();let d:any=null;if(t){try{d=JSON.parse(t)}catch{d=t}}
  if(!r.ok)throw new Error(typeof d==='object'?(d.message||d.error||JSON.stringify(d)):String(d||r.status));
  return d;
}
async function auth(path:string,body:any){
  const r=await fetch(`${URL}/auth/v1/${path}`,{method:'POST',headers:{apikey:ANON,'Content-Type':'application/json'},body:JSON.stringify(body)});
  const t=await r.text();let d:any=null;if(t){try{d=JSON.parse(t)}catch{d=t}}
  return {ok:r.ok,status:r.status,data:d};
}
async function adminUser(userId:string){
  const r=await fetch(`${URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`,{headers:serviceHeaders()});
  if(!r.ok)return null; return await r.json();
}
async function resolveEmail(identifier:string){
  const id=String(identifier||'').trim().toLowerCase();
  if(id.includes('@'))return id;
  const alias=normalize(id); if(alias.length<3)return null;
  const rows=await db(`rt85_login_aliases?alias=eq.${encodeURIComponent(alias)}&select=user_id&limit=1`);
  const uid=rows?.[0]?.user_id; if(!uid)return null;
  const u=await adminUser(uid); return String(u?.email||'').trim().toLowerCase()||null;
}
async function ensureUser(user:any,preferredRaw=''){
  if(!user?.id)return;
  const email=String(user.email||'').trim().toLowerCase();
  const fallback=normalize(email.split('@')[0]);
  const preferred=normalize(preferredRaw);
  const aliases=[preferred,fallback].filter(x=>x.length>=3);
  for(const alias of aliases){
    try{await db('rt85_login_aliases?on_conflict=alias',{method:'POST',headers:{Prefer:'resolution=ignore-duplicates,return=minimal'},body:{alias,user_id:user.id,source:alias===preferred&&preferred?'claimed':'email_localpart',updated_at:new Date().toISOString()}})}catch{}
  }
  let chosen=preferred||fallback||'governante';
  const existing=await db(`rt85_login_aliases?user_id=eq.${encodeURIComponent(user.id)}&select=alias,source&order=created_at.asc&limit=20`).catch(()=>[]);
  const claim=existing?.find((x:any)=>x.source==='claimed')||existing?.find((x:any)=>x.source==='player_name')||existing?.[0];
  if(claim?.alias)chosen=claim.alias;
  await db('rt_players?on_conflict=user_id',{method:'POST',headers:{Prefer:'resolution=merge-duplicates,return=minimal'},body:{user_id:user.id,username:chosen,anchor_x:500,anchor_y:500,last_seen_at:new Date().toISOString()}}).catch(()=>null);
}
function publicError(data:any,status:number){
  const code=String(data?.error_code||data?.code||'');
  const msg=String(data?.msg||data?.message||data?.error_description||data?.error||'');
  if(/not confirmed/i.test(msg)||code==='email_not_confirmed')return out({error:'E-mail ainda não confirmado. Confirme o e-mail ou use recuperação/código.'},403);
  if(status===429)return out({error:'Muitas tentativas. Aguarde um pouco e tente novamente.'},429);
  return out({error:'Credenciais inválidas ou conta indisponível.'},401);
}
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:H});
  if(req.method!=='POST')return out({error:'Método inválido'},405);
  try{
    const b=await req.json().catch(()=>({})); const action=String(b.action||'password_login');
    if(action==='health')return out({ok:true,version:85,alias_login:true});
    if(action==='password_login'){
      const identifier=String(b.identifier||'').trim(); const password=String(b.password||'');
      if(!identifier||password.length<6)return out({error:'Informe usuário/e-mail e senha.'},400);
      const email=await resolveEmail(identifier); if(!email)return out({error:'Credenciais inválidas ou conta indisponível.'},401);
      const r=await auth('token?grant_type=password',{email,password}); if(!r.ok)return publicError(r.data,r.status);
      await ensureUser(r.data?.user,identifier.includes('@')?'':identifier); return out(r.data);
    }
    if(action==='signup'){
      const email=String(b.email||'').trim().toLowerCase(); const password=String(b.password||''); const username=normalize(b.username);
      if(!email.includes('@')||password.length<8||username.length<3)return out({error:'Informe usuário, e-mail e senha com pelo menos 8 caracteres.'},400);
      const exists=await db(`rt85_login_aliases?alias=eq.${encodeURIComponent(username)}&select=alias&limit=1`); if(exists?.length)return out({error:'Nome de usuário já está em uso.'},409);
      const r=await auth('signup',{email,password,data:{username}}); if(!r.ok)return out({error:String(r.data?.msg||r.data?.message||r.data?.error_description||'Não foi possível criar a conta.')},r.status);
      if(r.data?.user?.id)await ensureUser(r.data.user,username); return out(r.data);
    }
    if(action==='request_otp'){
      const identifier=String(b.identifier||'').trim(); const email=await resolveEmail(identifier);
      if(email)await auth('otp',{email,create_user:false}).catch(()=>null);
      return out({ok:true,message:'Se a conta existir, o código/link de acesso foi enviado.'});
    }
    if(action==='verify_otp'){
      const identifier=String(b.identifier||'').trim(); const token=String(b.token||'').trim();
      if(token.length<6)return out({error:'Código inválido.'},400);
      const email=await resolveEmail(identifier); if(!email)return out({error:'Código inválido ou expirado.'},401);
      const r=await auth('verify',{type:'email',email,token}); if(!r.ok)return out({error:'Código inválido ou expirado.'},401);
      await ensureUser(r.data?.user,identifier.includes('@')?'':identifier); return out(r.data);
    }
    return out({error:'Ação desconhecida.'},400);
  }catch(e){console.error('rt-login-v85',e);return out({error:'Falha temporária de autenticação.'},500)}
});