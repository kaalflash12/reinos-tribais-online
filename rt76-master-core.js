'use strict';
(()=>{
  if(window.__RT76_MASTER_PLAN__||!window.RT76)return;
  window.__RT76_MASTER_PLAN__=true;
  const A=window.RT76;
  const S=()=>A.state();
  const D=()=>A.test.data();
  const n=v=>Math.max(0,Math.floor(Number(v)||0));
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const fmt=v=>new Intl.NumberFormat('pt-BR').format(n(v));
  const stamp=()=>Date.now();
  const uid=p=>`${p}_${Date.now()}_${Math.random().toString(36).slice(2,8)}`;
  const save=()=>A.save();
  const owned=()=>Object.values(S()?.villages||{}).filter(v=>v.owner==='player');
  const dist=(a,b)=>Math.hypot((a?.x||0)-(b?.x||0),(a?.y||0)-(b?.y||0));
  const totalTroops=t=>Object.values(t||{}).reduce((a,b)=>a+n(b),0);
  const clone=x=>JSON.parse(JSON.stringify(x));

  function ensure(){
    const s=S(); if(!s)return null;
    s.rt76||={};
    /* RT76_MASTER_BASE_INIT */
    s.rt76.scheduledCommands||=[];
    s.rt76.targetIntel||={};
    s.rt76.actionLog||=[];
    s.rt76.farm||={templates:{A:{spear:25},B:{axe:40,light:10},C:{light:40,spy:1}},cycleLimit:5};
    s.rt76.farm.templates||={A:{spear:25},B:{axe:40,light:10},C:{light:40,spy:1}};
    s.rt76.market||={minStock:{wood:5000,clay:5000,iron:5000},cycleLimit:3,autoEqualize:false,history:[]};
    s.rt76.market.minStock||={wood:5000,clay:5000,iron:5000};
    s.rt76.market.history||=[];
    s.rt76.manager||={researchPriority:[],autoScavenge:false,decisionLog:[],lastExtraRun:0};
    s.rt76.manager.researchPriority||=[];
    s.rt76.manager.decisionLog||=[];
    const m=s.rt76.master||=( {
      schema:2,
      commandPresets:[], targetGroups:[], waves:[], scheduledSupport:[], recallHistory:[],
      farmRules:{maxDistance:25,maxWall:8,maxLossPct:35,reattackMinutes:20,cycleLimit:5,barbarianOnly:true},
      intelHistory:{},
      marketRoutes:[], supplyRequests:[],
      jobs:[], jobHistory:[], aiJobs:[], aiJobHistory:[],
      governor:{profiles:{},lastRun:0}, villageRoles:{}, logisticsRules:[],
      alerts:[], notes:{},
      tribeProjects:[], contributionLog:[],
      trace:{mdSource:'Markdown(20260816-185951).md colado',mdLines:1349,globalComplete:false}
    });
    m.commandPresets||=[];m.targetGroups||=[];m.waves||=[];m.scheduledSupport||=[];m.recallHistory||=[];
    m.farmRules||={maxDistance:25,maxWall:8,maxLossPct:35,reattackMinutes:20,cycleLimit:5,barbarianOnly:true};
    m.intelHistory||={};m.marketRoutes||=[];m.supplyRequests||=[];m.jobs||=[];m.jobHistory||=[];m.aiJobs||=[];m.aiJobHistory||=[];
    m.governor||={profiles:{},lastRun:0};m.governor.profiles||={};m.villageRoles||={};m.logisticsRules||=[];m.alerts||=[];m.notes||={};
    m.tribeProjects||=[];m.contributionLog||=[];m.trace||={mdSource:'Markdown(20260816-185951).md colado',mdLines:1349,globalComplete:false};
    return m;
  }

  function log(type,message,data={}){
    const m=ensure(); if(!m)return;
    m.jobHistory.unshift({id:uid('log'),type,message,data,at:stamp()});
    m.jobHistory=m.jobHistory.slice(0,300); save();
  }

  function cleanTroops(sourceId,troops){
    const s=S(),v=s?.villages?.[String(sourceId)]; if(!v)throw Error('Aldeia de origem não encontrada.');
    const out={};
    for(const [k,d] of Object.entries(D().units)){
      if(d.movable===false)continue;
      const q=Math.min(n(v.units?.[k]),n(troops?.[k]));
      if(q)out[k]=q;
    }
    if(!totalTroops(out))throw Error('Selecione tropas disponíveis.');
    return out;
  }

  const Planner={
    savePreset(name,troops,kind='attack'){
      const m=ensure(),x={id:uid('preset'),name:String(name||'Preset'),kind:String(kind||'attack'),troops:clone(troops||{}),createdAt:stamp()};
      m.commandPresets.push(x);m.commandPresets=m.commandPresets.slice(-40);save();return clone(x);
    },
    deletePreset(id){const m=ensure(),before=m.commandPresets.length;m.commandPresets=m.commandPresets.filter(x=>x.id!==id);save();return before!==m.commandPresets.length;},
    createTargetGroup(name,ids){const m=ensure(),x={id:uid('group'),name:String(name||'Grupo'),targets:[...new Set((ids||[]).map(String))].filter(id=>S().villages[id]),createdAt:stamp()};m.targetGroups.push(x);m.targetGroups=m.targetGroups.slice(-30);save();return clone(x);},
    planSynchronized({targetId,orders,arrivalAt,gapMs=0}){
      const arr=Number(arrivalAt);if(!Number.isFinite(arr)||arr<=stamp())throw Error('Horário de chegada inválido.');
      const out=[];for(const [i,o] of (orders||[]).entries())out.push(A.scheduleAttack({sourceId:o.sourceId,targetId:String(targetId),troops:cleanTroops(o.sourceId,o.troops),kind:o.kind||'attack',arrivalAt:arr+i*n(gapMs)}));
      if(!out.length)throw Error('Nenhuma ordem foi informada.');
      const m=ensure();m.waves.push({id:uid('sync'),targetId:String(targetId),arrivalAt:arr,gapMs:n(gapMs),scheduledIds:out.map(x=>x.id),createdAt:stamp()});m.waves=m.waves.slice(-80);save();return clone(out);
    },
    planWave({sourceId,targetId,troops,arrivalAt,count=1,gapMs=1000,kind='attack'}){
      const c=Math.max(1,Math.min(20,n(count)||1)),orders=Array.from({length:c},()=>({sourceId:String(sourceId),troops:clone(troops),kind}));
      return this.planSynchronized({targetId,orders,arrivalAt,gapMs});
    },
    planFake({sourceId,targetId,arrivalAt,troops}){return A.scheduleAttack({sourceId:String(sourceId),targetId:String(targetId),troops:cleanTroops(sourceId,troops),kind:'fake',arrivalAt:Number(arrivalAt)});},
    scheduleSupport({sourceId,targetId,troops,arrivalAt}){
      if(typeof window.travelDuration!=='function'||typeof window.sendSupport!=='function')throw Error('Ponte de apoio não disponível.');
      const s=S(),src=s.villages[String(sourceId)],dst=s.villages[String(targetId)];if(!src||src.owner!=='player'||!dst)throw Error('Origem ou destino inválido.');
      const clean=cleanTroops(sourceId,troops),travel=window.travelDuration(src,dst,clean),arr=Number(arrivalAt),depart=arr-travel;if(!Number.isFinite(arr)||depart<stamp()+500)throw Error('Horário de apoio cedo demais.');
      const x={id:uid('support_sched'),sourceId:src.id,targetId:dst.id,troops:clean,departAt:depart,arrivalAt:arr,travelDuration:travel,status:'scheduled',createdAt:stamp()};
      ensure().scheduledSupport.push(x);ensure().scheduledSupport.sort((a,b)=>a.departAt-b.departAt);save();return clone(x);
    },
    processSupport(ts=stamp()){
      const m=ensure();let changed=false;
      for(const x of m.scheduledSupport){if(x.status!=='scheduled'||x.departAt>ts)continue;const src=S().villages[x.sourceId],dst=S().villages[x.targetId];if(!src||!dst||!Object.entries(x.troops).every(([k,q])=>n(src.units[k])>=n(q))){x.status='failed';x.error='Tropas/origem/destino indisponíveis';changed=true;continue}
        try{A.withVillage(src.id,()=>{const fd=new FormData();fd.set('targetId',dst.id);for(const [k,q] of Object.entries(x.troops))fd.set(`sup_${k}`,String(q));window.sendSupport(fd)});x.status='sent';x.sentAt=ts}catch(e){x.status='failed';x.error=String(e?.message||e)}changed=true;
      } if(changed)save();return changed;
    },
    recall(commandId){
      const s=S(),c=s.commands.find(x=>String(x.id)===String(commandId));if(!c||c.phase!=='outbound'||c.kind!=='attack')throw Error('Somente ataque ainda em viagem pode ser retirado.');
      const src=s.villages[c.sourceId];if(!src||src.owner!=='player')throw Error('Comando não pertence ao jogador.');
      const elapsed=Math.max(1000,stamp()-(c.startAt||stamp())),oldTarget=c.targetId;
      c.phase='return';c.sourceId=oldTarget;c.targetId=src.id;c.startAt=stamp();c.arriveAt=stamp()+elapsed;c.travelDuration=elapsed;c.loot={wood:0,clay:0,iron:0};c.recalledAt=stamp();
      ensure().recallHistory.unshift({commandId:c.id,sourceId:src.id,fromTargetId:oldTarget,returnAt:c.arriveAt,at:stamp()});ensure().recallHistory=ensure().recallHistory.slice(0,100);save();return clone(c);
    }
  };

  const Farm={
    rules(){return clone(ensure().farmRules);},
    setRules(x){Object.assign(ensure().farmRules,x||{});save();return this.rules();},
    setTemplate(name,troops){if(!['A','B','C'].includes(String(name)))throw Error('Template deve ser A, B ou C.');S().rt76.farm.templates[String(name)]=clone(troops||{});save();return clone(S().rt76.farm.templates[String(name)]);},
    candidates(){const s=S(),src=A.test.getActiveVillage(),r=this.rules();return Object.values(s.villages).filter(v=>v.id!==src.id&&(!r.barbarianOnly||v.owner==='barbarian')).map(v=>{const i=s.rt76.targetIntel?.[v.id]||{},d=dist(src,v),loss=Number(i.lossPct||0),wall=Number(i.wall||0),mins=i.lastVisit?(stamp()-i.lastVisit)/60000:Infinity;return {id:v.id,name:v.name,distance:d,wall,lossPct:loss,minutesSinceVisit:mins,recommendation:A.farmRecommendation(v.id),allowed:d<=Number(r.maxDistance||Infinity)&&wall<=Number(r.maxWall||Infinity)&&loss<=Number(r.maxLossPct||100)&&mins>=Number(r.reattackMinutes||0)}}).filter(x=>x.allowed).sort((a,b)=>a.distance-b.distance);},
    runBatch(limit){const max=Math.max(1,Math.min(30,n(limit)||n(this.rules().cycleLimit)||5));let sent=0,errors=[];for(const t of this.candidates()){if(sent>=max)break;try{A.farmAttack(t.id,t.recommendation);sent++}catch(e){errors.push({id:t.id,error:String(e?.message||e)})}}log('farm.batch','Lote de farm executado',{sent,errors});return {sent,errors};}
  };

  const Intel={
    observe(id){const s=S(),v=s.villages[String(id)];if(!v)throw Error('Alvo não encontrado.');const m=ensure(),list=m.intelHistory[v.id]||=([]),prev=list[0]||null,ti=s.rt76.targetIntel?.[v.id]||{};const snap={at:stamp(),id:v.id,name:v.name,owner:v.owner,ownerName:v.ownerName||'',tribe:v.tribe||'',points:n(v.points),x:v.x,y:v.y,wall:ti.wall??null,lastLoot:ti.lastLoot??null,fullness:ti.fullness??null,lossPct:ti.lossPct??null,pointDelta:prev?n(v.points)-n(prev.points):0};list.unshift(snap);m.intelHistory[v.id]=list.slice(0,40);save();return clone(snap);},
    history(id){return clone(ensure().intelHistory[String(id)]||[]);},
    classify(id){const h=this.history(id),v=S().villages[String(id)],src=A.test.getActiveVillage();if(!v)return null;const last=h[0]||this.observe(id),age=(stamp()-last.at)/3600000,delta=last.pointDelta||0,hostile=v.owner!=='player'&&!(S().player.tribe&&v.tribe===S().player.tribe),farmable=v.owner==='barbarian'&&(last.wall??0)<=ensure().farmRules.maxWall;return {growing:delta>0,inactive:age>24,strong:n(v.points)>n(src.points)*1.5,weak:n(v.points)<n(src.points)*.6,hostile,farmable};},
    incoming(command){const s=S(),c=typeof command==='object'?command:s.commands.find(x=>String(x.id)===String(command));if(!c)return null;const src=s.villages[c.sourceId],dst=s.villages[c.targetId],watch=n(dst?.buildings?.watchtower),troops=c.troops||{},entries=Object.entries(troops).filter(([,q])=>n(q)>0),total=entries.reduce((a,[,q])=>a+n(q),0),slow=entries.sort((a,b)=>(D().units[b[0]]?.speed||0)-(D().units[a[0]]?.speed||0))[0]?.[0]||null;return {arrivalAt:c.arriveAt,target:dst?`${dst.name} ${dst.x}|${dst.y}`:'?',origin:watch>=1&&src?`${src.name} ${src.x}|${src.y}`:'?',type:watch>=15?(c.attackType==='raid'?'Saque':'Ataque'):'?',size:watch>=8?(total<50?'pequeno':total<500?'médio':'grande'):'?',slowest:watch>=12?(D().units[slow]?.name||'?'):'?',exactTroops:watch>=20?clone(troops):null,watchtower:watch};}
  };

  const Market={
    addRoute(x){const m=ensure(),r={id:uid('route'),sourceId:String(x.sourceId),targetId:String(x.targetId),resource:String(x.resource||'wood'),amount:n(x.amount),minSource:n(x.minSource),targetMax:n(x.targetMax),intervalMs:Math.max(60000,n(x.intervalMs)||300000),lastRun:0,enabled:x.enabled!==false};if(!S().villages[r.sourceId]||!S().villages[r.targetId]||!['wood','clay','iron'].includes(r.resource)||r.amount<1)throw Error('Rota inválida.');m.marketRoutes.push(r);m.marketRoutes=m.marketRoutes.slice(-100);save();return clone(r);},
    removeRoute(id){const m=ensure(),b=m.marketRoutes.length;m.marketRoutes=m.marketRoutes.filter(x=>x.id!==id);save();return b!==m.marketRoutes.length;},
    request({targetId,resource,amount}){const m=ensure(),x={id:uid('supply'),targetId:String(targetId),resource:String(resource),amount:n(amount),status:'open',createdAt:stamp()};if(!S().villages[x.targetId]||!['wood','clay','iron'].includes(x.resource)||x.amount<1)throw Error('Pedido inválido.');m.supplyRequests.push(x);save();return clone(x);},
    fulfillRequests(limit=5){const m=ensure();let done=0;for(const x of m.supplyRequests.filter(x=>x.status==='open')){if(done>=limit)break;const target=S().villages[x.targetId],donor=owned().filter(v=>v.id!==target.id&&(v.buildings.market||0)>0).sort((a,b)=>n(b.resources[x.resource])-n(a.resources[x.resource]))[0];if(!donor||n(donor.resources[x.resource])<x.amount)continue;try{A.engine.market.send(donor.id,target.id,{[x.resource]:x.amount});x.status='sent';x.sourceId=donor.id;x.sentAt=stamp();done++}catch(e){x.error=String(e?.message||e)}}if(done)save();return done;},
    runRoutes(ts=stamp()){const m=ensure();let sent=0;for(const r of m.marketRoutes.filter(r=>r.enabled)){if(ts-r.lastRun<r.intervalMs)continue;const a=S().villages[r.sourceId],b=S().villages[r.targetId];if(!a||!b)continue;const have=n(a.resources[r.resource]),there=n(b.resources[r.resource]);if(have-r.amount<r.minSource|| (r.targetMax>0&&there>=r.targetMax))continue;try{A.engine.market.send(a.id,b.id,{[r.resource]:r.amount});r.lastRun=ts;sent++}catch(e){r.lastError=String(e?.message||e);r.lastRun=ts}}if(sent)save();return sent;}
  };

  const JOB_TYPES=['BUILD','RECRUIT','RESEARCH','FARM','TRADE','DEFEND','EXPAND'];
  const Jobs={
    enqueue(type,payload={},runAt=stamp(),owner='player'){type=String(type).toUpperCase();if(!JOB_TYPES.includes(type))throw Error('Tipo de job inválido.');const x={id:uid('job'),type,payload:clone(payload),runAt:Number(runAt)||stamp(),owner,status:'queued',createdAt:stamp(),attempts:0};ensure().jobs.push(x);save();return clone(x);},
    cancel(id){const x=ensure().jobs.find(x=>x.id===id);if(!x||x.status!=='queued')return false;x.status='cancelled';x.cancelledAt=stamp();save();return true;},
    execute(x){x.attempts++;const p=x.payload||{};switch(x.type){case'BUILD':return A.engine.village.build(p.villageId,p.building);case'RECRUIT':return A.engine.army.recruit(p.villageId,p.unit,p.qty);case'RESEARCH':return A.engine.research.start(p.id);case'FARM':return A.farmAttack(p.targetId,p.template||'A');case'TRADE':return A.engine.market.send(p.sourceId,p.targetId,p.resources||{});case'DEFEND':return Planner.scheduleSupport(p);case'EXPAND':return A.engine.army.attack(p.sourceId,p.targetId,p.troops||{noble:1},{attackType:'normal'});default:throw Error('Job sem executor.');}},
    process(ts=stamp(),limit=10){const m=ensure();let count=0;for(const x of m.jobs.filter(x=>x.status==='queued'&&x.runAt<=ts)){if(count>=limit)break;try{this.execute(x);x.status='done';x.finishedAt=ts}catch(e){x.status='failed';x.error=String(e?.message||e);x.finishedAt=ts}m.jobHistory.unshift(clone(x));count++}m.jobs=m.jobs.slice(-300);m.jobHistory=m.jobHistory.slice(0,300);if(count)save();return count;},
    list(){return clone(ensure().jobs);}
  };

  const AI_PROFILES={
    raider:{label:'Saqueador',priorities:['FARM','RECRUIT','ATTACK','ECONOMY']},
    warden:{label:'Guardião',priorities:['WALL','DEFEND','RECRUIT','HIDE']},
    expander:{label:'Expansionista',priorities:['ECONOMY','ACADEMY','NOBLE','EXPAND']},
    opportunist:{label:'Oportunista',priorities:['OBSERVE','WEAK_TARGET','FARM','ATTACK']}
  };
  function planAIJobs(ts=stamp()){
    const m=ensure(),ais=Object.values(S().villages).filter(v=>v.owner!=='player'&&v.owner!=='barbarian'&&!v._onlineRemote);if(!ais.length)return 0;let added=0;
    for(const v of ais){const profile=typeof window.aiPersonality==='function'?window.aiPersonality(v):['raider','warden','expander','opportunist'][Math.abs(String(v.id).split('').reduce((a,c)=>a+c.charCodeAt(0),0))%4];const exists=m.aiJobs.some(j=>j.villageId===v.id&&j.status==='planned'&&ts-j.createdAt<120000);if(exists)continue;const x={id:uid('aijob'),villageId:v.id,ownerName:v.ownerName||'IA',profile,priorities:clone(AI_PROFILES[profile]?.priorities||[]),status:'planned',createdAt:ts};m.aiJobs.push(x);added++;}
    m.aiJobs=m.aiJobs.slice(-400);if(added)save();return added;
  }
  function reconcileAIJobs(ts=stamp()){
    const m=ensure(),activity=A.ai?.activity?.()||[];let changed=0;for(const j of m.aiJobs.filter(j=>j.status==='planned')){const hit=activity.find(a=>a.villageId===j.villageId&&a.at>=j.createdAt);if(hit){j.status='executed';j.finishedAt=hit.at;j.changes=clone(hit.changes||[]);m.aiJobHistory.unshift(clone(j));changed++;}}
    m.aiJobHistory=m.aiJobHistory.slice(0,300);if(changed)save();return changed;
  }

  const GOVERNOR_PROFILES={
    economic:{label:'Econômica',buildings:['timber','clay','iron','warehouse','farm','market'],units:[]},
    military:{label:'Militar',buildings:['barracks','stable','garage','smith','farm'],units:['axe','light','ram']},
    defensive:{label:'Defensiva',buildings:['wall','barracks','farm','warehouse','hide'],units:['spear','sword','heavy']},
    expansion:{label:'Expansionista',buildings:['main','warehouse','farm','academy','market'],units:['noble']}
  };
  const Governor={
    setRole(villageId,role){if(!GOVERNOR_PROFILES[role])throw Error('Perfil inválido.');ensure().villageRoles[String(villageId)]=role;save();return role;},
    role(villageId){return ensure().villageRoles[String(villageId)]||'economic';},
    run(villageId){const v=S().villages[String(villageId)];if(!v||v.owner!=='player')throw Error('Aldeia inválida.');const role=this.role(v.id),p=GOVERNOR_PROFILES[role],decisions=[];
      const buildKey=p.buildings.slice().sort((a,b)=>n(v.buildings[a])-n(v.buildings[b]))[0];if(buildKey){try{A.engine.village.build(v.id,buildKey);decisions.push({type:'BUILD',key:buildKey})}catch(e){decisions.push({type:'BUILD_BLOCKED',key:buildKey,error:String(e?.message||e)})}}
      const unit=p.units.find(k=>D().units[k]&&n(v.units[k])<Math.max(20,n(v.points)/20));if(unit){try{A.engine.army.recruit(v.id,unit,5);decisions.push({type:'RECRUIT',key:unit,qty:5})}catch(e){decisions.push({type:'RECRUIT_BLOCKED',key:unit,error:String(e?.message||e)})}}
      const m=ensure();m.governor.profiles[v.id]={role,lastRun:stamp(),decisions};m.governor.lastRun=stamp();save();return clone(decisions);}
  };

  const Empire={
    setRole:(id,role)=>Governor.setRole(id,role),
    addLogisticsRule(x){const m=ensure(),r={id:uid('logistics'),villageId:String(x.villageId),resource:String(x.resource),minimum:n(x.minimum),enabled:x.enabled!==false};if(!S().villages[r.villageId]||!['wood','clay','iron'].includes(r.resource))throw Error('Regra logística inválida.');m.logisticsRules.push(r);save();return clone(r);},
    runLogistics(){const m=ensure();let made=0;for(const r of m.logisticsRules.filter(r=>r.enabled)){const v=S().villages[r.villageId];if(!v||n(v.resources[r.resource])>=r.minimum)continue;const open=m.supplyRequests.some(x=>x.status==='open'&&x.targetId===v.id&&x.resource===r.resource);if(!open){Market.request({targetId:v.id,resource:r.resource,amount:r.minimum-n(v.resources[r.resource])});made++;}}if(made)Market.fulfillRequests(10);return made;},
    batchRecruit(unit,qty,ids=null){const out=[];for(const v of owned().filter(v=>!ids||ids.map(String).includes(v.id))){try{A.engine.army.recruit(v.id,unit,qty);out.push({villageId:v.id,ok:true})}catch(e){out.push({villageId:v.id,ok:false,error:String(e?.message||e)})}}save();return out;},
    batchBuild(building,ids=null){const out=[];for(const v of owned().filter(v=>!ids||ids.map(String).includes(v.id))){try{A.engine.village.build(v.id,building);out.push({villageId:v.id,ok:true})}catch(e){out.push({villageId:v.id,ok:false,error:String(e?.message||e)})}}save();return out;}
  };

  const TribeProjects={
    templates:{roads:{name:'Estradas Tribais',cost:{wood:15000,clay:10000,iron:5000}},fortifications:{name:'Fortificações Tribais',cost:{wood:10000,clay:20000,iron:15000}},trade:{name:'Entreposto Tribal',cost:{wood:12000,clay:12000,iron:12000}}},
    create(template){const t=this.templates[template];if(!t||!S().player.tribe)throw Error('Projeto ou tribo inválido.');const m=ensure(),x={id:uid('tribeproj'),template,name:t.name,cost:clone(t.cost),progress:{wood:0,clay:0,iron:0},status:'active',createdAt:stamp()};m.tribeProjects.push(x);save();return clone(x);},
    contribute(projectId,resources){const m=ensure(),p=m.tribeProjects.find(x=>x.id===projectId&&x.status==='active'),td=S().player.tribeData;if(!p||!td)throw Error('Projeto/tesouro indisponível.');for(const k of ['wood','clay','iron']){const need=Math.max(0,n(p.cost[k])-n(p.progress[k])),q=Math.min(need,n(resources?.[k]),n(td.treasury?.[k]));td.treasury[k]-=q;p.progress[k]+=q;if(q)m.contributionLog.unshift({at:stamp(),projectId:p.id,player:S().player.name,resource:k,amount:q});}if(['wood','clay','iron'].every(k=>n(p.progress[k])>=n(p.cost[k]))){p.status='complete';p.completedAt=stamp();td.xp=n(td.xp)+250;}m.contributionLog=m.contributionLog.slice(0,200);save();return clone(p);},
    ranking(){const sums={};for(const x of ensure().contributionLog)sums[x.player]=(sums[x.player]||0)+n(x.amount);return Object.entries(sums).map(([player,total])=>({player,total})).sort((a,b)=>b.total-a.total);}
  };

  const Alerts={
    compute(){const s=S(),out=[];for(const v of owned()){const cap=typeof window.storageCapacity==='function'?window.storageCapacity(v):Infinity;if(!v.buildQueue?.length)out.push({type:'build_idle',villageId:v.id,text:`${v.name}: fila de construção vazia`});if(Number.isFinite(cap)&&['wood','clay','iron'].some(k=>n(v.resources[k])>=cap*.9))out.push({type:'storage_full',villageId:v.id,text:`${v.name}: armazém perto do limite`});const incoming=s.commands.filter(c=>c.kind==='attack'&&c.phase==='outbound'&&c.targetId===v.id);if(incoming.length)out.push({type:'incoming',villageId:v.id,text:`${v.name}: ${incoming.length} ataque(s) chegando`});}
      ensure().alerts=out.slice(0,100);return clone(out);}
  };

  A.master={ensure:()=>clone(ensure()),planner:Planner,farm:Farm,intel:Intel,market:Market,jobs:Jobs,ai:{profiles:clone(AI_PROFILES),planJobs:planAIJobs,reconcile:reconcileAIJobs},governor:{profiles:clone(GOVERNOR_PROFILES),...Governor},empire:Empire,tribeProjects:TribeProjects,alerts:Alerts};
  window.RT=A.engine;

  function formTroops(v,prefix='mp_'){return Object.entries(D().units).filter(([,d])=>d.movable!==false).map(([k,d])=>`<label>${d.icon||''} ${esc(d.name)}<input name="${prefix}${k}" type="number" min="0" max="${n(v.units[k])}" value="0"></label>`).join('')}
  function plannerCard(){const s=S(),m=ensure(),v=A.test.getActiveVillage(),targets=Object.values(s.villages).filter(x=>x.owner!=='player').slice(0,100),out=s.commands.filter(c=>c.kind==='attack'&&c.phase==='outbound'&&s.villages[c.sourceId]?.owner==='player');return `<section class="dashboard-card rt76-master-card" id="rt76-master-planner"><h2>⚔ Planejador Militar Completo</h2><p class="small">Ondas, fakes, chegada sincronizada, presets e retirada de comandos ainda em viagem.</p><form id="rt76-wave-form"><div class="rt76-master-grid"><label>Alvo<select name="targetId">${targets.map(t=>`<option value="${t.id}">${esc(t.name)} ${t.x}|${t.y}</option>`).join('')}</select></label><label>Chegada<input name="arrival" type="datetime-local" step="1" required></label><label>Ondas<input name="count" type="number" min="1" max="20" value="1"></label><label>Intervalo ms<input name="gap" type="number" min="0" max="60000" value="1000"></label><label>Tipo<select name="kind"><option value="attack">Ataque</option><option value="fake">Fake</option></select></label></div><div class="rt76-master-units">${formTroops(v,'wave_')}</div><button class="btn primary">Programar ondas</button></form>${out.length?`<h3>Retirada</h3>${out.slice(0,20).map(c=>`<div class="queue-item">#${c.id} → ${esc(s.villages[c.targetId]?.name||'?')} <button class="btn danger small-btn" data-rt76-recall="${c.id}">Retirar</button></div>`).join('')}`:''}<div class="notice info">Presets salvos: ${m.commandPresets.length} • grupos de alvos: ${m.targetGroups.length} • ondas registradas: ${m.waves.length}</div></section>`}
  function farmRulesCard(){const r=Farm.rules();return `<section class="dashboard-card rt76-master-card" id="rt76-master-farm-rules"><h2>🎯 Regras completas do Smart Farm</h2><form id="rt76-farm-rules-form"><div class="rt76-master-grid"><label>Distância máx.<input name="maxDistance" type="number" min="1" value="${r.maxDistance}"></label><label>Muralha máx.<input name="maxWall" type="number" min="0" value="${r.maxWall}"></label><label>Perdas máx. %<input name="maxLossPct" type="number" min="0" max="100" value="${r.maxLossPct}"></label><label>Reatacar após min<input name="reattackMinutes" type="number" min="0" value="${r.reattackMinutes}"></label><label>Limite/ciclo<input name="cycleLimit" type="number" min="1" max="30" value="${r.cycleLimit}"></label></div><button class="btn primary">Salvar regras</button> <button type="button" class="btn" data-rt76-farm-batch>Executar lote elegível</button></form></section>`}
  function marketCard(){const m=ensure(),vill=owned();return `<section class="dashboard-card rt76-master-card" id="rt76-master-logistics"><h2>🚚 Rotas e abastecimento</h2><form id="rt76-route-form"><div class="rt76-master-grid"><label>Origem<select name="sourceId">${vill.map(v=>`<option value="${v.id}">${esc(v.name)}</option>`).join('')}</select></label><label>Destino<select name="targetId">${vill.map(v=>`<option value="${v.id}">${esc(v.name)}</option>`).join('')}</select></label><label>Recurso<select name="resource"><option value="wood">Madeira</option><option value="clay">Argila</option><option value="iron">Ferro</option></select></label><label>Quantidade<input name="amount" type="number" min="1" value="1000"></label><label>Reserva origem<input name="minSource" type="number" min="0" value="5000"></label><label>Intervalo min<input name="interval" type="number" min="1" value="5"></label></div><button class="btn primary">Criar rota real</button> <button type="button" class="btn" data-rt76-run-routes>Executar rotas</button></form><div class="small">Rotas: ${m.marketRoutes.length} • pedidos: ${m.supplyRequests.filter(x=>x.status==='open').length}</div>${m.marketRoutes.slice(-12).map(r=>`<div class="queue-item">${esc(S().villages[r.sourceId]?.name)} → ${esc(S().villages[r.targetId]?.name)} • ${r.resource} ${fmt(r.amount)} <button class="btn danger small-btn" data-rt76-del-route="${r.id}">Excluir</button></div>`).join('')}</section>`}
  function governorCard(){const vill=owned();return `<section class="dashboard-card rt76-master-card" id="rt76-master-governor"><h2>🏛 Governador por aldeia</h2><p class="small">Executa somente ações normais com custo e pré-requisitos reais.</p>${vill.map(v=>`<div class="queue-item"><b>${esc(v.name)}</b> <select data-rt76-role="${v.id}">${Object.entries(GOVERNOR_PROFILES).map(([k,p])=>`<option value="${k}" ${Governor.role(v.id)===k?'selected':''}>${p.label}</option>`).join('')}</select> <button class="btn small-btn" data-rt76-run-governor="${v.id}">Executar 1 ciclo</button></div>`).join('')}</section>`}
  function systemsCard(){const m=ensure(),alerts=Alerts.compute();return `<section class="dashboard-card rt76-master-card" id="rt76-master-engine"><h2>⚙ Motor / Jobs / Observabilidade</h2><div class="stat-grid"><div class="stat-card"><div class="muted">Jobs</div><div class="value">${m.jobs.filter(x=>x.status==='queued').length}</div></div><div class="stat-card"><div class="muted">AIJobs</div><div class="value">${m.aiJobs.filter(x=>x.status==='planned').length}</div></div><div class="stat-card"><div class="muted">Alertas</div><div class="value">${alerts.length}</div></div><div class="stat-card"><div class="muted">MD</div><div class="value">1349 linhas</div></div></div><div class="notice info"><b>API única:</b> RT.village.build / RT.army.recruit / RT.army.attack / RT.market.send / RT.research.start / RT.world.scan</div>${alerts.slice(0,12).map(a=>`<div class="queue-item">⚠ ${esc(a.text)}</div>`).join('')}</section>`}
  function intelCard(){const ids=A.map?.state?.().selected||[],rows=ids.map(id=>{const v=S().villages[id],h=Intel.history(id),c=v?Intel.classify(id):null;return v?`<div class="queue-item"><b>${esc(v.name)} ${v.x}|${v.y}</b> • ${h.length} observação(ões) • ${c?.growing?'crescendo ':''}${c?.inactive?'inativo ':''}${c?.hostile?'hostil ':''}${c?.farmable?'farmável':''} <button class="btn small-btn" data-rt76-observe="${v.id}">Observar</button></div>`:''}).join('');return `<section class="dashboard-card rt76-master-card" id="rt76-master-intel"><h2>🔭 Histórico de inteligência</h2><button class="btn" data-rt76-observe-selected>Observar selecionados</button>${rows||'<p class="muted">Selecione alvos no painel de inteligência do mapa.</p>'}</section>`}
  function tribeCard(){if(!S().player.tribe||!S().player.tribeData)return'';const m=ensure(),td=S().player.tribeData;return `<section class="dashboard-card rt76-master-card" id="rt76-master-tribe"><h2>🏰 Projetos coletivos da tribo</h2><div class="small">Tesouro: 🪵${fmt(td.treasury?.wood)} 🧱${fmt(td.treasury?.clay)} ⛓️${fmt(td.treasury?.iron)}</div><div class="btn-row"><button class="btn" data-rt76-create-project="roads">Estradas</button><button class="btn" data-rt76-create-project="fortifications">Fortificações</button><button class="btn" data-rt76-create-project="trade">Entreposto</button></div>${m.tribeProjects.map(p=>`<div class="queue-item"><b>${esc(p.name)}</b> • ${p.status} • 🪵${fmt(p.progress.wood)}/${fmt(p.cost.wood)} 🧱${fmt(p.progress.clay)}/${fmt(p.cost.clay)} ⛓️${fmt(p.progress.iron)}/${fmt(p.cost.iron)} ${p.status==='active'?`<button class="btn small-btn" data-rt76-fund-project="${p.id}">Financiar do tesouro</button>`:''}</div>`).join('')}</section>`}

  function inject(){/* RT76_MASTER_INJECT_ENSURE */ ensure();const s=S(),p=document.querySelector('.content-panel');if(!s||!p)return;const title=document.querySelector('.panel-title')?.textContent||'';if(/Praça/.test(title)&&!document.querySelector('#rt76-master-planner'))p.insertAdjacentHTML('beforeend',plannerCard()+farmRulesCard());if(/^Mercado/.test(title)&&!document.querySelector('#rt76-master-logistics'))p.insertAdjacentHTML('beforeend',marketCard());if(/Gerente/.test(title)&&!document.querySelector('#rt76-master-governor'))p.insertAdjacentHTML('beforeend',governorCard());if(/Central de Sistemas/.test(title)&&!document.querySelector('#rt76-master-engine'))p.insertAdjacentHTML('beforeend',systemsCard());if((String(window.currentView||'')==='map'||/Mapa/.test(title))&&!document.querySelector('#rt76-master-intel'))p.insertAdjacentHTML('beforeend',intelCard());if(/^Tribo/.test(title)&&!document.querySelector('#rt76-master-tribe'))p.insertAdjacentHTML('beforeend',tribeCard())}

  document.addEventListener('submit',e=>{const f=e.target;if(f.id==='rt76-wave-form'){e.preventDefault();const fd=new FormData(f),v=A.test.getActiveVillage(),troops={};for(const k of Object.keys(D().units))troops[k]=n(fd.get('wave_'+k));try{Planner.planWave({sourceId:v.id,targetId:fd.get('targetId'),troops,arrivalAt:Date.parse(String(fd.get('arrival'))),count:n(fd.get('count'))||1,gapMs:n(fd.get('gap')),kind:String(fd.get('kind')||'attack')});alert('Ondas programadas.')}catch(x){alert(x.message)}A.test.render();return}if(f.id==='rt76-farm-rules-form'){e.preventDefault();const fd=new FormData(f);Farm.setRules({maxDistance:+fd.get('maxDistance'),maxWall:+fd.get('maxWall'),maxLossPct:+fd.get('maxLossPct'),reattackMinutes:+fd.get('reattackMinutes'),cycleLimit:+fd.get('cycleLimit')});A.test.render();return}if(f.id==='rt76-route-form'){e.preventDefault();const fd=new FormData(f);try{Market.addRoute({sourceId:fd.get('sourceId'),targetId:fd.get('targetId'),resource:fd.get('resource'),amount:+fd.get('amount'),minSource:+fd.get('minSource'),intervalMs:(+fd.get('interval')||5)*60000});A.test.render()}catch(x){alert(x.message)}return}},true);
  document.addEventListener('change',e=>{const x=e.target.closest('[data-rt76-role]');if(x){Governor.setRole(x.dataset.rt76Role,x.value);A.test.render()}},true);
  document.addEventListener('click',e=>{let x=e.target.closest('[data-rt76-recall]');if(x){try{Planner.recall(x.dataset.rt76Recall)}catch(err){alert(err.message)}A.test.render();return}x=e.target.closest('[data-rt76-farm-batch]');if(x){const r=Farm.runBatch();alert(`${r.sent} farm(s) enviado(s).`);A.test.render();return}x=e.target.closest('[data-rt76-run-routes]');if(x){alert(`${Market.runRoutes(stamp())} rota(s) executada(s).`);A.test.render();return}x=e.target.closest('[data-rt76-del-route]');if(x){Market.removeRoute(x.dataset.rt76DelRoute);A.test.render();return}x=e.target.closest('[data-rt76-run-governor]');if(x){Governor.run(x.dataset.rt76RunGovernor);A.test.render();return}x=e.target.closest('[data-rt76-observe]');if(x){Intel.observe(x.dataset.rt76Observe);A.test.render();return}x=e.target.closest('[data-rt76-observe-selected]');if(x){for(const id of A.map?.state?.().selected||[])try{Intel.observe(id)}catch(_){}A.test.render();return}x=e.target.closest('[data-rt76-create-project]');if(x){try{TribeProjects.create(x.dataset.rt76CreateProject)}catch(err){alert(err.message)}A.test.render();return}x=e.target.closest('[data-rt76-fund-project]');if(x){try{TribeProjects.contribute(x.dataset.rt76FundProject,{wood:5000,clay:5000,iron:5000})}catch(err){alert(err.message)}A.test.render();return}},true);

  document.addEventListener('contextmenu',e=>{const cell=e.target.closest('.map-cell[data-target],.rt22-map-cell[data-target]');if(!cell||!S())return;e.preventDefault();const id=cell.dataset.target,v=S().villages[id];if(!v)return;let menu=document.getElementById('rt76-map-context');if(menu)menu.remove();menu=document.createElement('div');menu.id='rt76-map-context';menu.innerHTML=`<b>${esc(v.name)} ${v.x}|${v.y}</b><button data-rt76-context-open="${id}">Abrir</button><button data-rt76-context-select="${id}">Selecionar</button><button data-rt76-context-observe="${id}">Observar</button>`;menu.style.left=e.clientX+'px';menu.style.top=e.clientY+'px';document.body.appendChild(menu)},true);
  document.addEventListener('click',e=>{const m=document.getElementById('rt76-map-context');const a=e.target.closest('[data-rt76-context-open]');if(a){m?.remove();document.querySelector(`[data-target="${CSS.escape(a.dataset.rt76ContextOpen)}"]`)?.click();return}const b=e.target.closest('[data-rt76-context-select]');if(b){A.map?.toggleTarget?.(b.dataset.rt76ContextSelect);m?.remove();A.test.render();return}const c=e.target.closest('[data-rt76-context-observe]');if(c){Intel.observe(c.dataset.rt76ContextObserve);m?.remove();A.test.render();return}if(m&&!e.target.closest('#rt76-map-context'))m.remove()},true);

  const css=document.createElement('style');css.id='rt76-master-css';css.textContent=`.rt76-master-card{margin-top:18px;border:2px solid #665022;background:linear-gradient(145deg,#fff4cef5,#d8bd7ef0)}.rt76-master-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}.rt76-master-grid input,.rt76-master-grid select,.rt76-master-card select{width:100%;padding:7px}.rt76-master-units{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:7px;margin:10px 0}.rt76-master-units label{display:flex;justify-content:space-between;gap:6px;padding:6px;border:1px solid #a4834e;background:#fff8e2}.rt76-master-units input{width:70px}#rt76-map-context{position:fixed;z-index:999999;min-width:200px;padding:8px;background:#17130e;color:#f2e3b8;border:1px solid #c49a49;box-shadow:0 8px 30px #0008;display:grid;gap:5px}#rt76-map-context button{padding:7px;background:#4d3517;color:#fff0c4;border:1px solid #8d6c32}@media(max-width:700px){.rt76-master-grid{grid-template-columns:1fr}.rt76-master-units{grid-template-columns:1fr 1fr}}`;document.head.appendChild(css);

  const obs=new MutationObserver(()=>queueMicrotask(inject));obs.observe(document.getElementById('app')||document.body,{childList:true,subtree:true});
  setInterval(()=>{try{Planner.processSupport(stamp());Jobs.process(stamp(),6);Market.runRoutes(stamp());Empire.runLogistics();planAIJobs(stamp());reconcileAIJobs(stamp());inject()}catch(e){console.error('RT76 master scheduler',e)}},5000);
  /* RT76_MASTER_STATE_WATCH */ setInterval(()=>{try{if(S())ensure()}catch(_){}},200);
  ensure();inject();
})();
