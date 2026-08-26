'use strict';
(()=>{
  if(window.__RT89_STRATEGY_CLIENT__) return;
  window.__RT89_STRATEGY_CLIENT__=true;

  const SESSION_KEY='reinos_tribais_supabase_session_v60_browser';
  const DEFAULT_WORLD='d5a546fb-316d-4332-ae92-1886d80b07df';

  const session=()=>{try{return JSON.parse(sessionStorage.getItem(SESSION_KEY)||'null')}catch{return null}};
  const cleanBase=v=>String(v||'').trim().replace(/\/$/,'');
  const base=()=>cleanBase(window.REINO_TRIBAL_API_BASE||window.ReinoTribalTurso?.apiBase||'');
  const emit=(name,detail={})=>window.dispatchEvent(new CustomEvent(name,{detail}));

  async function call(action,payload={}){
    const apiBase=base();
    if(!apiBase)throw new Error('API do Reino Tribal não configurada.');
    const token=String(session()?.access_token||'');
    const publicAction=action==='health'||action==='catalog';
    if(!publicAction&&!token)throw Object.assign(new Error('Sessão necessária para comandos estratégicos.'),{status:401});
    const headers={'Content-Type':'application/json','Accept':'application/json'};
    if(token)headers.Authorization=`Bearer ${token}`;
    const response=await fetch(`${apiBase}/api/strategy`,{
      method:'POST',headers,body:JSON.stringify({action,...payload}),cache:'no-store'
    });
    const text=await response.text();
    let data=null;try{data=text?JSON.parse(text):null}catch{data={error:text||`HTTP ${response.status}`}}
    if(!response.ok)throw Object.assign(new Error(data?.error||`HTTP ${response.status}`),{status:response.status,data});
    return data;
  }

  async function supports(){
    const apiBase=base();if(!apiBase)return false;
    try{
      const response=await fetch(`${apiBase}/health`,{cache:'no-store',headers:{Accept:'application/json'}});
      const data=await response.json();
      return Boolean(response.ok&&data?.ok===true&&data?.strategy===true&&data?.strategy_endpoint==='/api/strategy');
    }catch{return false}
  }

  function worldId(value=''){
    return String(value||window.REINO_TRIBAL_WORLD_ID||DEFAULT_WORLD);
  }

  function notifyRealtime(command){
    const type=String(command?.realtime_event||'');
    if(!type)return;
    try{
      window.ReinoTribalRealtime?.notify?.(type,{
        command_id:command.id,
        command_type:command.type,
        status:command.status,
        village_id:command.village_id,
      });
    }catch{}
  }

  async function create(type,payload,options={}){
    const data=await call('create',{
      world_id:worldId(options.world_id),
      type:String(type||''),
      payload:payload||{},
      scheduled_at:options.scheduled_at||'',
      idempotency_key:options.idempotency_key||'',
    });
    emit('reino:strategy-command',{action:'create',...data});
    notifyRealtime(data?.command);
    return data;
  }

  async function list(options={}){
    return call('list',{world_id:worldId(options.world_id),status:options.status||'',limit:options.limit||100});
  }

  async function get(commandId){return call('get',{command_id:String(commandId||'')})}
  async function summary(world=''){return call('summary',{world_id:worldId(world)})}
  async function audit(commandId){return call('audit',{command_id:String(commandId||'')})}

  async function transition(action,commandId,result){
    const command=await call(action,{command_id:String(commandId||''),...(result===undefined?{}:{result})});
    emit('reino:strategy-command',{action,command});
    notifyRealtime(command);
    return command;
  }

  const cancel=commandId=>transition('cancel',commandId);
  const complete=(commandId,result=null)=>transition('complete',commandId,result);
  const fail=(commandId,result=null)=>transition('fail',commandId,result);

  window.ReinoTribalStrategy={
    version:'rt89-v1',
    supports,
    health:()=>call('health'),
    catalog:()=>call('catalog'),
    create,list,get,summary,audit,cancel,complete,fail,
    buildUpgrade:(villageId,building,targetLevel,options={})=>create('build_upgrade',{village_id:villageId,building,target_level:targetLevel},options),
    recruit:(villageId,unit,quantity,options={})=>create('recruit_units',{village_id:villageId,unit,quantity},options),
    attack:(villageId,targetVillageId,troops,options={})=>create('attack',{village_id:villageId,target_village_id:targetVillageId,troops},options),
    spy:(villageId,targetVillageId,spies,options={})=>create('spy',{village_id:villageId,target_village_id:targetVillageId,spies},options),
    support:(villageId,targetVillageId,troops,options={})=>create('support',{village_id:villageId,target_village_id:targetVillageId,troops},options),
    transfer:(villageId,targetVillageId,resources,options={})=>create('transfer_resources',{village_id:villageId,target_village_id:targetVillageId,resources},options),
    collectDeposit:(villageId,depositId,options={})=>create('collect_deposit',{village_id:villageId,deposit_id:depositId},options),
    get apiBase(){return base()},
  };

  emit('reino:strategy-ready',{version:'rt89-v1'});
})();
