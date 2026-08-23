'use strict';
(()=>{
  if(window.__RT_TURSO_BRIDGE__) return;
  window.__RT_TURSO_BRIDGE__=true;
  window.__RT_SERVER_ACTIONS_ENABLED__=false;

  const ORIGINAL_FETCH=window.fetch.bind(window);
  const LEGACY_ORIGIN='https://rlyiwlwzrdgvcwawrnpl.supabase.co';
  const SESSION_KEY='reinos_tribais_supabase_session_v60_browser';
  const API_BASE_KEY='reino_tribal_api_base';
  const DEFAULT_WORLD='d5a546fb-316d-4332-ae92-1886d80b07df';

  const cleanBase=v=>String(v||'').trim().replace(/\/$/,'');
  function apiBase(){
    const configured=cleanBase(window.REINO_TRIBAL_API_BASE||localStorage.getItem(API_BASE_KEY)||'');
    if(configured)return configured;
    if(/\.vercel\.app$/i.test(location.hostname))return location.origin;
    return '';
  }
  const urlOf=input=>typeof input==='string'?input:(input?.url||'');
  const parseBody=body=>{try{return typeof body==='string'?JSON.parse(body):body||{}}catch{return {}}};
  const session=()=>{try{return JSON.parse(sessionStorage.getItem(SESSION_KEY)||'null')}catch{return null}};
  const authHeader=init=>String(init?.headers?.Authorization||init?.headers?.authorization||'');
  const tokenFrom=(init={})=>{
    const h=authHeader(init);if(/^Bearer\s+/i.test(h))return h.replace(/^Bearer\s+/i,'').trim();
    return session()?.access_token||'';
  };
  const jsonResponse=(data,status=200,headers={})=>new Response(JSON.stringify(data??null),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',...headers}});
  const errorResponse=(message,status=400)=>jsonResponse({error:String(message||'Falha na requisição.')},status);

  async function call(path,action,payload={},token=''){
    const base=apiBase();
    if(!base)throw new Error('Backend Turso ainda não está apontado para a URL da API do Reino Tribal.');
    const headers={'Content-Type':'application/json'};
    if(token)headers.Authorization=`Bearer ${token}`;
    const r=await ORIGINAL_FETCH(`${base}${path}`,{method:'POST',headers,body:JSON.stringify({action,...payload}),cache:'no-store'});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null}catch{data={error:text||`HTTP ${r.status}`}}
    if(!r.ok)throw Object.assign(new Error(data?.error||data?.message||`HTTP ${r.status}`),{status:r.status,data});
    return data;
  }
  const api=(action,payload={},token='')=>call('/api/reino',action,payload,token);
  const adminApi=(action,payload={},token='')=>call('/api/admin',action,payload,token);

  function eqParam(params,key,def=''){
    const v=String(params.get(key)||'');return v.startsWith('eq.')?decodeURIComponent(v.slice(3)):def;
  }
  function preferToken(init){return tokenFrom(init)}

  async function legacyAuth(url,init){
    const method=String(init?.method||'GET').toUpperCase();const body=parseBody(init?.body);const token=preferToken(init);
    if(url.includes('/auth/v1/token?grant_type=password')&&method==='POST'){
      const data=await api('login',{identifier:String(body.email||body.identifier||''),password:String(body.password||'')});
      return jsonResponse(data);
    }
    if(url.includes('/auth/v1/token?grant_type=refresh_token')&&method==='POST'){
      const cached=session();const raw=String(body.refresh_token||cached?.refresh_token||cached?.access_token||'');
      if(!raw)return errorResponse('Sessão expirada.',401);
      const me=await api('me',{},raw);
      const next={...(cached||{}),access_token:raw,refresh_token:raw,token_type:'bearer',expires_in:2592000,expires_at:Math.floor(Date.now()/1000)+2592000,user:me?.user};
      return jsonResponse(next);
    }
    if(url.endsWith('/auth/v1/signup')&&method==='POST'){
      const data=await api('register',{email:String(body.email||''),username:String(body.username||''),password:String(body.password||'')});
      return jsonResponse(data);
    }
    if(url.endsWith('/auth/v1/logout')&&method==='POST'){
      if(token)await api('logout',{},token).catch(()=>null);
      return jsonResponse({ok:true});
    }
    if(url.endsWith('/auth/v1/user')&&method==='GET'){
      const data=await api('me',{},token);return jsonResponse(data?.user||data);
    }
    if(url.endsWith('/auth/v1/user')&&method==='PUT')return errorResponse('Troca de senha de jogador por link ainda não está habilitada no Turso.',501);
    if(url.includes('/auth/v1/otp')||url.includes('/auth/v1/verify'))return errorResponse('Login por código de e-mail foi removido nesta migração. Use usuário/e-mail e senha.',501);
    return null;
  }

  async function legacyRest(url,init){
    const method=String(init?.method||'GET').toUpperCase();const body=parseBody(init?.body);const token=preferToken(init);const u=new URL(url);const path=u.pathname;const p=u.searchParams;
    if(path==='/rest/v1/worlds'&&method==='GET'){
      const rows=await api('list_worlds',{},token);return jsonResponse(rows);
    }
    if(path==='/rest/v1/player_worlds'&&method==='GET'){
      const world=eqParam(p,'world_id','');const user=eqParam(p,'user_id','');
      if(world&&user){const row=await api('player_world_get',{world_id:world},token);return jsonResponse(row?[row]:[])}
      const rows=await api('memberships',{},token);return jsonResponse(rows||[]);
    }
    if(path==='/rest/v1/player_worlds'&&(method==='PATCH'||method==='POST')){
      const world=eqParam(p,'world_id',String(body.world_id||DEFAULT_WORLD));
      const data=await api('player_world_update',{world_id:world,patch:body},token);return jsonResponse(data?[data]:[],200);
    }
    if(path==='/rest/v1/game_saves'&&method==='GET'){
      const world=eqParam(p,'world_id',DEFAULT_WORLD);const row=await api('load_save',{world_id:world},token);return jsonResponse(row?[row]:[]);
    }
    if(path==='/rest/v1/game_saves'&&method==='DELETE'){
      const world=eqParam(p,'world_id',DEFAULT_WORLD);await api('delete_save',{world_id:world},token);return jsonResponse(null,204);
    }
    if(path==='/rest/v1/game_saves'&&(method==='POST'||method==='PATCH')){
      const world=String(body.world_id||eqParam(p,'world_id',DEFAULT_WORLD));const state=body.state??body.state_json;
      const data=await api('save',{world_id:world,state},token);return jsonResponse(data);
    }
    if(path==='/rest/v1/rpc/rt50_join_world'&&method==='POST'){
      const data=await api('join_world',{world_id:body.p_world_id,player_name:body.p_player_name},token);return jsonResponse(data);
    }
    return null;
  }

  async function legacyFunctions(url,init){
    const method=String(init?.method||'POST').toUpperCase();if(method!=='POST')return null;
    const body=parseBody(init?.body);const path=new URL(url).pathname;
    if(path==='/functions/v1/rt-login-v85'){
      if(body.action==='health')return jsonResponse(await api('health'));
      if(body.action==='password_login')return jsonResponse(await api('login',{identifier:body.identifier,password:body.password}));
      if(body.action==='signup')return jsonResponse(await api('register',{email:body.email,username:body.username,password:body.password}));
      return errorResponse('Ação de e-mail/código não existe mais no backend Turso.',501);
    }
    if(path==='/functions/v1/rt-admin-recovery-v102'){
      try{return jsonResponse(await api('admin_recover',{token:body.token,password:body.password}))}catch(e){return errorResponse(e.message,e.status||400)}
    }
    if(path==='/functions/v1/rt-admin-v64'){
      if(body.action==='login'){
        try{
          const s=await api('login',{identifier:'reinos_admin',password:body.password});
          if(s?.user?.role!=='admin')return errorResponse('Conta não possui permissão administrativa.',403);
          return jsonResponse({ok:true,token:s.access_token,admin:{id:s.user.id,username:s.user.username,role:'superadmin'}});
        }catch(e){return errorResponse(e.message,e.status||401)}
      }
      const adminToken=String(init?.headers?.['x-admin-token']||init?.headers?.['X-Admin-Token']||sessionStorage.getItem('rt60_admin_token')||'');
      try{return jsonResponse(await adminApi(body.action,body,adminToken))}catch(e){return errorResponse(e.message,e.status||400)}
    }
    if(path==='/functions/v1/rt-admin-logout-v67'){
      const adminToken=String(init?.headers?.['x-admin-token']||init?.headers?.['X-Admin-Token']||sessionStorage.getItem('rt60_admin_token')||'');
      try{return jsonResponse(await adminApi('logout',{},adminToken))}catch{return jsonResponse({ok:true})}
    }
    return null;
  }

  window.fetch=async function(input,init={}){
    const url=urlOf(input);
    if(!url.startsWith(LEGACY_ORIGIN))return ORIGINAL_FETCH(input,init);
    try{
      const a=await legacyAuth(url,init);if(a)return a;
      const f=await legacyFunctions(url,init);if(f)return f;
      const r=await legacyRest(url,init);if(r)return r;
      return errorResponse('Este módulo online ainda apontava para o banco antigo e foi bloqueado durante a migração para Turso.',503);
    }catch(e){return errorResponse(e?.message||e,e?.status||500)}
  };

  function enhance(){
    const form=document.querySelector('#rt18-login-form');if(!form||form.dataset.rtTurso==='1')return;
    form.dataset.rtTurso='1';
    document.querySelectorAll('[data-rt85-code],[data-rt85-code-panel]').forEach(x=>x.remove());
    const note=document.createElement('p');note.className='small';note.dataset.rtTursoNote='1';note.textContent=apiBase()?'Conta e save online conectados ao backend exclusivo Turso do Reino Tribal.':'Backend Turso preparado; falta somente apontar a URL privada da API.';
    form.insertAdjacentElement('afterend',note);
  }
  const pulse=()=>enhance();new MutationObserver(pulse).observe(document.documentElement,{childList:true,subtree:true});setInterval(pulse,1200);pulse();

  window.ReinoTribalTurso={
    version:'1.0.4-turso',
    get apiBase(){return apiBase()},
    configure(base){const v=cleanBase(base);if(v)localStorage.setItem(API_BASE_KEY,v);else localStorage.removeItem(API_BASE_KEY);location.reload()},
    health(){return api('health')},
    blockLegacySupabase:true,
  };
})();
