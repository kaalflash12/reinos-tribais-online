const C={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'content-type,apikey,authorization',
  'Access-Control-Allow-Methods':'POST,OPTIONS',
  'Content-Type':'application/json; charset=utf-8'
};
const URL=Deno.env.get('SUPABASE_URL')||'';
const SERVICE=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const out=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:C});
async function sha(s:string){const b=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('')}
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  if(req.method!=='POST')return out({error:'Método inválido.'},405);
  try{
    const b=await req.json();
    const token=String(b.token||'').trim();
    const username=String(b.username||'reinos_admin').trim();
    const password=String(b.password||'');
    if(token.length<32)return out({error:'Código de recuperação inválido.'},400);
    if(password.length<12)return out({error:'A nova senha precisa ter pelo menos 12 caracteres.'},400);
    const r=await fetch(`${URL}/rest/v1/rpc/rt102_admin_recovery_consume`,{
      method:'POST',
      headers:{apikey:SERVICE,Authorization:`Bearer ${SERVICE}`,'Content-Type':'application/json'},
      body:JSON.stringify({p_token_hash:await sha(token),p_username:username,p_password:password})
    });
    const text=await r.text();let data:any=null;try{data=text?JSON.parse(text):null}catch{data=text}
    if(!r.ok)return out({error:data?.message||data?.error||'Falha ao atualizar a senha.'},400);
    if(data!==true)return out({error:'Código expirado, já usado ou inválido.'},403);
    return out({ok:true,username,reauth:true});
  }catch(e:any){console.error(e);return out({error:e?.message||String(e)},400)}
});
