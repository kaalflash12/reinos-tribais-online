'use strict';
(()=>{
  if(window.__RT88_REALTIME_CLIENT__) return;
  window.__RT88_REALTIME_CLIENT__=true;

  const SESSION_KEY='reinos_tribais_supabase_session_v60_browser';
  const DEFAULT_WORLD='d5a546fb-316d-4332-ae92-1886d80b07df';
  const MAX_BACKOFF=15000;

  let socket=null;
  let state='idle';
  let authenticated=false;
  let selectedWorld='';
  let reconnectTimer=0;
  let reconnectAttempt=0;
  let manualClose=false;
  let seq=0;
  const pending=new Map();

  const session=()=>{try{return JSON.parse(sessionStorage.getItem(SESSION_KEY)||'null')}catch{return null}};
  const emit=(name,detail={})=>window.dispatchEvent(new CustomEvent(name,{detail}));
  const setState=(next,detail={})=>{state=next;emit('reino:realtime-status',{state,...detail})};

  function apiBase(){
    const direct=String(window.REINO_TRIBAL_API_BASE||'').trim().replace(/\/$/,'');
    if(direct)return direct;
    const bridge=String(window.ReinoTribalTurso?.apiBase||'').trim().replace(/\/$/,'');
    return bridge;
  }

  function wsUrl(){
    const base=apiBase();
    if(!base)return '';
    try{
      const u=new URL(base,location.href);
      u.protocol=u.protocol==='https:'?'wss:':'ws:';
      u.pathname='/ws';u.search='';u.hash='';
      return u.toString();
    }catch{return ''}
  }

  function send(type,data={},id=''){
    if(!socket||socket.readyState!==WebSocket.OPEN)return false;
    const message={type,data};
    if(id)message.id=id;
    socket.send(JSON.stringify(message));
    return true;
  }

  function request(type,data={},timeout=6000){
    const id=`rt88-${Date.now()}-${++seq}`;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{pending.delete(id);reject(new Error(`Timeout realtime: ${type}`))},timeout);
      pending.set(id,{resolve,reject,timer,type});
      if(!send(type,data,id)){
        clearTimeout(timer);pending.delete(id);reject(new Error('WebSocket realtime não está conectado.'));
      }
    });
  }

  function settle(message){
    if(!message?.id||!pending.has(message.id))return false;
    const item=pending.get(message.id);pending.delete(message.id);clearTimeout(item.timer);
    if(message.type==='System/error')item.reject(Object.assign(new Error(message?.data?.message||'Erro realtime.'),{data:message.data}));
    else item.resolve(message);
    return true;
  }

  function dispatchMessage(message){
    emit('reino:realtime',{message});
    if(message.type.startsWith('Presence/'))emit('reino:presence',{message});
    if(message.type==='Village/changed')emit('reino:village-changed',{message});
    if(message.type==='Command/changed')emit('reino:command-changed',{message});
    if(message.type==='Report/new')emit('reino:report-new',{message});
    if(message.type==='Chat/tribe')emit('reino:tribe-chat',{message});
    if(message.type==='Resources/changed')emit('reino:resources-changed',{message});
    if(message.type==='Army/changed')emit('reino:army-changed',{message});
    if(message.type==='Building/changed')emit('reino:building-changed',{message});
    if(message.type==='World/changed')emit('reino:world-changed',{message});
  }

  async function authenticateAndSelect(){
    const current=session();
    const token=String(current?.access_token||'');
    if(!token){
      authenticated=false;selectedWorld='';setState('waiting-session');return;
    }
    const auth=await request('Authentication/session',{token});
    authenticated=Boolean(auth?.data?.authenticated);
    if(!authenticated)throw new Error('Sessão realtime não autenticada.');

    const desired=String(window.REINO_TRIBAL_WORLD_ID||DEFAULT_WORLD);
    const selected=await request('World/select',{world_id:desired});
    selectedWorld=String(selected?.data?.world_id||'');
    await request('Realtime/subscribe',{});
    reconnectAttempt=0;
    setState('online',{world_id:selectedWorld,user:auth?.data?.user||null});
  }

  function scheduleReconnect(){
    if(manualClose||reconnectTimer)return;
    const current=session();
    if(!current?.access_token){setState('waiting-session');return}
    const delay=Math.min(MAX_BACKOFF,750*Math.pow(2,Math.min(5,reconnectAttempt++)));
    setState('reconnecting',{delay});
    reconnectTimer=setTimeout(()=>{reconnectTimer=0;connect()},delay);
  }

  function connect(){
    manualClose=false;
    const url=wsUrl();
    if(!url){setState('unavailable',{reason:'api-base'});return false}
    if(socket&&(socket.readyState===WebSocket.OPEN||socket.readyState===WebSocket.CONNECTING))return true;

    try{
      setState('connecting',{url});
      socket=new WebSocket(url);
      socket.addEventListener('open',()=>{
        setState('handshake');
      });
      socket.addEventListener('message',event=>{
        let message;try{message=JSON.parse(String(event.data))}catch{return}
        settle(message);
        dispatchMessage(message);
        if(message.type==='System/welcome'){
          authenticateAndSelect().catch(error=>{
            setState('auth-error',{message:String(error?.message||error)});
            try{socket?.close(4001,'auth failed')}catch{}
          });
        }
      });
      socket.addEventListener('close',event=>{
        authenticated=false;selectedWorld='';socket=null;
        for(const [id,item] of pending){clearTimeout(item.timer);item.reject(new Error('WebSocket realtime fechado.'));pending.delete(id)}
        setState(manualClose?'closed':'offline',{code:event.code,reason:event.reason});
        scheduleReconnect();
      });
      socket.addEventListener('error',()=>setState('error'));
      return true;
    }catch(error){
      socket=null;setState('error',{message:String(error?.message||error)});scheduleReconnect();return false;
    }
  }

  function disconnect(){
    manualClose=true;
    if(reconnectTimer){clearTimeout(reconnectTimer);reconnectTimer=0}
    try{socket?.close(1000,'manual')}catch{}
    socket=null;authenticated=false;selectedWorld='';setState('closed');
  }

  function notify(eventType,hint={}){
    if(!authenticated||!selectedWorld)return false;
    return send('Event/notify',{event_type:String(eventType||''),hint:hint&&typeof hint==='object'?hint:{}});
  }

  function ping(payload={}){return request('System/ping',payload)}

  window.ReinoTribalRealtime={
    version:'rt88-v1',
    connect,disconnect,notify,ping,
    get state(){return state},
    get online(){return state==='online'},
    get authenticated(){return authenticated},
    get worldId(){return selectedWorld},
    get url(){return wsUrl()},
  };

  window.addEventListener('online',()=>connect());
  window.addEventListener('offline',()=>{try{socket?.close(4000,'browser offline')}catch{}});
  window.addEventListener('storage',event=>{if(event.key===SESSION_KEY){disconnect();setTimeout(connect,50)}});

  const boot=()=>{
    if(document.visibilityState==='hidden')return;
    if(session()?.access_token)connect();else setState('waiting-session');
  };
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&!socket)boot()});
  setTimeout(boot,0);
})();
