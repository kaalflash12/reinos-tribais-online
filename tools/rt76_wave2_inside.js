/* RT76_WAVE2_START */
{
  const rt76w2=()=>{if(!state)return null;state.rt76||={};const r=state.rt76;r.map||={selected:[],favorites:[],filter:'all',query:''};r.map.selected||=[];r.map.favorites||=[];r.aiActivity||=[];return r};
  const rt76MapSave=()=>{dirty=true;saveState(true)};
  const rt76ToggleTarget=id=>{const r=rt76w2();if(!r)return[];id=String(id);const a=r.map.selected,i=a.indexOf(id);if(i>=0)a.splice(i,1);else a.push(id);r.map.selected=a.slice(-100);rt76MapSave();return [...r.map.selected]};
  const rt76ToggleFavorite=id=>{const r=rt76w2();if(!r)return[];id=String(id);const a=r.map.favorites,i=a.indexOf(id);if(i>=0)a.splice(i,1);else a.push(id);r.map.favorites=a.slice(-100);rt76MapSave();return [...r.map.favorites]};
  const rt76SelectedCoords=()=>{const r=rt76w2();return (r?.map.selected||[]).map(id=>state.villages[id]).filter(Boolean).map(v=>`${v.x}|${v.y}`).join(' ')};
  const rt76Scan=(opts={})=>{if(!state)return[];const origin=opts.originId?state.villages[String(opts.originId)]:getActiveVillage(),q=String(opts.query||'').trim().toLowerCase(),kind=String(opts.kind||'all'),max=Number(opts.maxDistance)||Infinity;return Object.values(state.villages).filter(v=>{if(v.id===origin?.id)return false;if(kind!=='all'&&String(v.owner)!==kind)return false;if(q&&!`${v.name||''} ${v.ownerName||''} ${v.x}|${v.y}`.toLowerCase().includes(q))return false;if(origin&&Math.hypot(v.x-origin.x,v.y-origin.y)>max)return false;return true}).sort((a,b)=>origin?Math.hypot(a.x-origin.x,a.y-origin.y)-Math.hypot(b.x-origin.x,b.y-origin.y):0).map(v=>({id:v.id,name:v.name,owner:v.owner,ownerName:v.ownerName,x:v.x,y:v.y,points:v.points||0,distance:origin?Math.hypot(v.x-origin.x,v.y-origin.y):0,lastIntel:state.rt76?.targetIntel?.[v.id]||null}));};
  const rt76Build=(villageId,key)=>rt76WithVillage(villageId,()=>queueBuilding(key));
  const rt76Recruit=(villageId,key,qty)=>rt76WithVillage(villageId,()=>queueRecruit(key,qty));
  const rt76Attack=(sourceId,targetId,troops,options={})=>rt76WithVillage(sourceId,()=>sendAttack(targetId,troops,options));
  const rt76Send=(sourceId,targetId,payload)=>RT76.sendResources(sourceId,targetId,payload);
  const rt76Research=id=>queueResearch(id);
  const rt76ActionAPI={
    village:{build:rt76Build},
    army:{recruit:rt76Recruit,attack:rt76Attack,schedule:RT76.scheduleAttack},
    market:{send:rt76Send,equalize:RT76.equalizeResources},
    research:{start:rt76Research},
    world:{scan:rt76Scan,selectTarget:rt76ToggleTarget,favorite:rt76ToggleFavorite,selectedCoords:rt76SelectedCoords},
    save:()=>saveState(true)
  };
  RT76.engine=rt76ActionAPI;
  RT76.map={scan:rt76Scan,toggleTarget:rt76ToggleTarget,toggleFavorite:rt76ToggleFavorite,selectedCoords:rt76SelectedCoords,clear:()=>{const r=rt76w2();if(r){r.map.selected=[];rt76MapSave()}return[]},state:()=>deepClone(rt76w2()?.map||{})};

  const rt76AiSig=v=>({points:Number(v.points)||0,buildings:Object.values(v.buildings||{}).reduce((a,b)=>a+(Number(b)||0),0),units:Object.values(v.units||{}).reduce((a,b)=>a+(Number(b)||0),0),resources:RESOURCE_KEYS.reduce((a,k)=>a+(Number(v.resources?.[k])||0),0)});
  const RT76_AI_BASE=processAI;
  processAI=function(ts){
    if(!state)return RT76_AI_BASE(ts);
    const before={};for(const v of Object.values(state.villages).filter(v=>v.owner==='ai'))before[v.id]=rt76AiSig(v);
    const cmdBefore=state.commands.length,out=RT76_AI_BASE(ts),r=rt76w2();
    if(r&&out){
      for(const v of Object.values(state.villages).filter(v=>v.owner==='ai')){
        const a=before[v.id]||{},b=rt76AiSig(v),changes=[];
        if(b.buildings!==a.buildings)changes.push('BUILD');
        if(b.units!==a.units)changes.push('RECRUIT/LOSS');
        if(b.points!==a.points)changes.push('GROWTH');
        if(b.resources!==a.resources)changes.push('ECONOMY');
        if(changes.length)r.aiActivity.unshift({at:ts,villageId:v.id,ownerName:v.ownerName||'IA',changes,before:a,after:b});
      }
      if(state.commands.length>cmdBefore)r.aiActivity.unshift({at:ts,villageId:null,ownerName:'IA',changes:['COMMAND'],commandsAdded:state.commands.length-cmdBefore});
      r.aiActivity=r.aiActivity.slice(0,150);dirty=true;
    }
    return out;
  };
  window.processAI=processAI;
  RT76.ai={activity:()=>deepClone(rt76w2()?.aiActivity||[]),process:ts=>processAI(ts)};
  if(RT76.test)RT76.test.processAI=ts=>processAI(ts);
  rt76w2();
  window.__RT76_WAVE2_APPLIED__=true;
}
/* RT76_WAVE2_END */