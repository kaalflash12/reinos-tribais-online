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
  try{
    const xhr=new XMLHttpRequest();
    xhr.open('GET','rt76-master-core.js?v=79.1',false);
    xhr.send(null);
    if(xhr.status<200||xhr.status>=300)throw Error('RT76 master core HTTP '+xhr.status);
    window.MutationObserver=RT76DebouncedMutationObserver;
    const script=document.createElement('script');
    script.id='rt76-master-core-runtime';
    script.textContent=xhr.responseText+'\n//# sourceURL=rt76-master-core.js';
    (document.head||document.documentElement).appendChild(script);
    script.remove();
  }catch(e){
    console.error('RT76 master compat loader',e);
  }finally{
    window.MutationObserver=NativeMO;
  }
})();
