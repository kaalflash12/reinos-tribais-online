const C={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json; charset=utf-8'};
const SB=Deno.env.get('SUPABASE_URL')||'';
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  if(req.method!=='POST')return new Response(JSON.stringify({error:'Método inválido.'}),{status:405,headers:C});
  const headers:any={'Content-Type':'application/json',apikey:req.headers.get('apikey')||'',Authorization:req.headers.get('authorization')||''};
  const body=await req.text();
  const r=await fetch(`${SB}/functions/v1/rt-multiplayer`,{method:'POST',headers,body});
  const text=await r.text();
  let data:any=null;try{data=text?JSON.parse(text):null}catch{data=text}
  if(data&&typeof data==='object'&&!Array.isArray(data)){data.version=60;data.router_revision='rt81.4';}
  return new Response(typeof data==='string'?data:JSON.stringify(data),{status:r.status,headers:C});
});
