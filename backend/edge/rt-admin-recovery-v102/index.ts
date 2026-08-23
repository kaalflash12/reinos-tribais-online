const CORS={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'content-type,apikey,authorization',
  'Access-Control-Allow-Methods':'POST,OPTIONS',
  'Content-Type':'application/json; charset=utf-8'
};
const URL=Deno.env.get('SUPABASE_URL')||'';
const SERVICE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const out=(data:any,status=200)=>new Response(JSON.stringify(data),{status,headers:CORS});
async function sha256(value:string){
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:CORS});
  if(req.method!=='POST')return out({error:'Método inválido'},405);
  try{
    const body=await req.json().catch(()=>({}));
    const token=String(body?.token||'').trim();
    const password=String(body?.password||'');
    if(token.length<32)return out({error:'Código de recuperação inválido ou expirado.'},400);
    if(password.length<12||password.length>256)return out({error:'A nova senha precisa ter entre 12 e 256 caracteres.'},400);
    const r=await fetch(`${URL}/rest/v1/rpc/rt58_admin_bootstrap_password`,{
      method:'POST',
      headers:{apikey:SERVICE,Authorization:`Bearer ${SERVICE}`,'Content-Type':'application/json'},
      body:JSON.stringify({p_token_hash:await sha256(token),p_username:'reinos_admin',p_password:password})
    });
    const text=await r.text();
    let value:any=null;try{value=text?JSON.parse(text):null}catch{value=text}
    if(!r.ok)throw new Error(typeof value==='object'?(value?.message||value?.hint||JSON.stringify(value)):String(value||r.status));
    if(value!==true)return out({error:'Código de recuperação inválido ou expirado.'},401);
    return out({ok:true,username:'reinos_admin'});
  }catch(error:any){
    console.error('admin-recovery-failed',error?.message||String(error));
    return out({error:'Não foi possível atualizar a senha administrativa.'},400);
  }
});
