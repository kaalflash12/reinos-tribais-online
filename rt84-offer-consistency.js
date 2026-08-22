'use strict';
(()=>{
  if(window.__RT84_OFFER_CONSISTENCY__) return;
  window.__RT84_OFFER_CONSISTENCY__=true;
  const num=v=>Math.max(0,Math.floor(Number(v)||0));
  function configured(node){
    const itemId=node?.state?.itemId||node?.state?.item_id||null;
    if(!itemId) return null;
    const fallback=Math.max(20,70+Math.max(1,num(node?.level))*12);
    const price=Math.max(20,num(node?.state?.price||node?.offer?.price||fallback));
    return {itemId:String(itemId),price};
  }
  function syncNode(node){
    const offer=configured(node);
    if(!offer) return node;
    node.offer={...(node.offer||{}),...offer};
    return node;
  }
  function syncAll(){
    try{
      const nodes=window.RT76?.state?.()?.world?.nodes||[];
      nodes.forEach(syncNode);
    }catch(err){console.error('RT84 offer sync',err)}
  }
  function install(){
    const api=window.RT84World;
    if(!api||api.__offerConsistency) return !!api?.__offerConsistency;
    const baseOffline=api.offline;
    const baseDetails=api.details;
    api.offline=(node,mode)=>baseOffline(syncNode(node),mode);
    api.details=node=>baseDetails(syncNode(node));
    api.syncConfiguredOffers=syncAll;
    api.__offerConsistency=true;
    syncAll();
    return true;
  }
  let tries=0;
  const boot=setInterval(()=>{
    tries++;
    syncAll();
    if(install()||tries>100) clearInterval(boot);
  },100);
  new MutationObserver(()=>{syncAll();install()}).observe(document.body||document.documentElement,{childList:true,subtree:true});
  setInterval(syncAll,1500);
})();