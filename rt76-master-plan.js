'use strict';
(()=>{
  if(window.__RT76_MASTER_COMPAT_LOADER__)return;
  window.__RT76_MASTER_COMPAT_LOADER__=true;
  const NativeMO=window.MutationObserver;
  class RT76DebouncedMutationObserver{
    constructor(callback){
      this.callback=callback;this.pending=false;this.batch=[];
      this.inner=new NativeMO((records)=>{
        this.batch.push(...records);
        if(this.pending)return;
        this.pending=true;
        setTimeout(()=>{
          this.pending=false;
          const rows=this.batch.splice(0);
          try{this.callback(rows,this)}catch(e){console.error('RT76 master observer',e)}
        },120);
      });
    }
    observe(target,options){return this.inner.observe(target,options)}
    disconnect(){this.batch.length=0;return this.inner.disconnect()}
    takeRecords(){return [...this.batch.splice(0),...this.inner.takeRecords()]}
  }
  const executeCore=(src)=>{
    window.MutationObserver=RT76DebouncedMutationObserver;
    try{
      const script=document.createElement('script');
      script.id='rt76-master-core-runtime';
      script.textContent=src+'\n//# sourceURL=rt76-master-core.js';
      (document.head||document.documentElement).appendChild(script);
      script.remove();
      if(!window.__RT76_MASTER_PLAN__||!window.RT76?.master)throw Error('RT76 master core não inicializou.');
      window.__RT76_MASTER_COMPAT_READY__=true;
      window.dispatchEvent(new CustomEvent('rt76-master-ready'));
    }finally{
      window.MutationObserver=NativeMO;
    }
  };
  fetch('rt76-master-core.js?v=79.1',{cache:'no-store'})
    .then(r=>{if(!r.ok)throw Error('RT76 master core HTTP '+r.status);return r.text()})
    .then(executeCore)
    .catch(e=>{window.__RT76_MASTER_COMPAT_ERROR__=String(e?.message||e);console.error('RT76 master compat loader',e)});
})();
