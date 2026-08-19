'use strict';
(()=>{
  if(window.__RT80_ADMIN_RUNTIME__)return;
  window.__RT80_ADMIN_RUNTIME__=true;
  let queued=false;
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
  const legacy=/\bRT(?:[1-7]\d)(?:\.\d+)?\b/gi;

  function normalizeText(root){
    if(!root)return;
    const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode(node){
      const p=node.parentElement;
      if(!p||['SCRIPT','STYLE','TEXTAREA','OPTION'].includes(p.tagName))return NodeFilter.FILTER_REJECT;
      const t=node.nodeValue||'';
      legacy.lastIndex=0;
      return legacy.test(t)||/Versão\s+79\b/i.test(t)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT;
    }});
    const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
    nodes.forEach(n=>{
      const before=n.nodeValue||'';
      const after=before.replace(/Versão\s+79\b/gi,'Versão RT80').replace(/\bRT(?:[1-7]\d)(?:\.\d+)?\b/gi,'RT80');
      if(after!==before)n.nodeValue=after;
    });
  }

  function normalizeHeader(shell){
    const top=$('.rt60-admin-top',shell);if(!top)return;
    const h=$('h1',top);
    if(h){
      const before=h.textContent||'REINOS TRIBAIS • CENTRAL OPERACIONAL';
      const after=before.replace(/\bRT(?:[1-7]\d)(?:\.\d+)?\b/gi,'RT80');
      if(after!==before)h.textContent=after;
    }
    const p=$('p',top);if(p){
      const before=p.textContent||'';
      let after=before.replace(/backend\s+v\d+(?:\.\d+)?/i,'backend online');
      after=after.replace(/interface\s+guiada\s+RT\d+(?:\.\d+)?/i,'interface guiada RT80');
      after=after.replace(/\bRT(?:[1-7]\d)(?:\.\d+)?\b/gi,'RT80');
      if(after!==before)p.textContent=after;
    }
  }

  function accessibility(shell){
    $$('.rt60-admin-nav button',shell).forEach(btn=>{if(!btn.getAttribute('aria-label'))btn.setAttribute('aria-label',(btn.textContent||'Seção administrativa').trim())});
    $$('table th',shell).forEach(th=>{if(!th.getAttribute('scope'))th.setAttribute('scope','col')});
    $$('input[placeholder]',shell).forEach(inp=>{if(!inp.getAttribute('aria-label'))inp.setAttribute('aria-label',inp.getAttribute('placeholder')||'Campo administrativo')});
    $$('button',shell).forEach(btn=>{if(!btn.getAttribute('aria-label')&&!(btn.textContent||'').trim()&&btn.title)btn.setAttribute('aria-label',btn.title)});
    $$('.rt64-modal,.rt60-admin-modal').forEach(modal=>{
      if(modal.getAttribute('role')!=='dialog')modal.setAttribute('role','dialog');
      if(modal.getAttribute('aria-modal')!=='true')modal.setAttribute('aria-modal','true');
      const title=$('h2',modal);if(title&&!title.id){title.id='rt80-admin-dialog-'+Math.random().toString(36).slice(2,9);modal.setAttribute('aria-labelledby',title.id)}
    });
  }

  function markEmptyStates(shell){
    $$('.rt60-admin-empty',shell).forEach(el=>{if(!el.classList.contains('rt80-admin-empty'))el.classList.add('rt80-admin-empty');if(!el.dataset.rt80Enhanced){el.dataset.rt80Enhanced='1';el.setAttribute('role','status')}});
    $$('td[colspan]',shell).forEach(td=>{const t=(td.textContent||'').trim();if(/^(sem|nenhum|nenhuma)/i.test(t)){if(!td.classList.contains('rt80-admin-empty-cell'))td.classList.add('rt80-admin-empty-cell');if(td.getAttribute('role')!=='status')td.setAttribute('role','status')}});
  }

  function ensure(){
    const shell=$('.rt60-admin-shell');
    if(shell){
      normalizeText(shell);normalizeHeader(shell);accessibility(shell);markEmptyStates(shell);
      if(shell.dataset.rt80AdminReady!=='1')shell.dataset.rt80AdminReady='1';
      if(!document.body.classList.contains('rt80-admin-mode'))document.body.classList.add('rt80-admin-mode');
    }else if(document.body.classList.contains('rt80-admin-mode'))document.body.classList.remove('rt80-admin-mode');
    $$('.rt64-modal,.rt60-admin-modal').forEach(m=>{normalizeText(m);accessibility(document);if(m.dataset.rt80AdminModal!=='1')m.dataset.rt80AdminModal='1'});
  }
  function schedule(){if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;try{ensure()}catch(e){console.error('RT80 admin visual ensure',e)}})}
  new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class','hidden','style']});
  window.addEventListener('resize',schedule,{passive:true});
  window.addEventListener('DOMContentLoaded',schedule);
  setInterval(schedule,3000);schedule();
  window.RT80AdminVisual={version:'80.5',refresh:ensure};
})();
