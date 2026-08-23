'use strict';
(()=>{
  if(window.__REINO_TRIBAL_BRANDING__) return;
  window.__REINO_TRIBAL_BRANDING__=true;

  const PRODUCT_NAME='Reino Tribal';
  const PUBLIC_VERSION='1.0.2';
  const REVISION_RE=/\bRT\s*\d+(?:\.\d+)*\b/gi;
  const BRAND_RE=/\bReinos Tribais\b/gi;
  const SKIP=new Set(['SCRIPT','STYLE','CODE','PRE','TEXTAREA','INPUT','OPTION']);

  window.REINO_TRIBAL=Object.freeze({name:PRODUCT_NAME,version:PUBLIC_VERSION});

  function cleanText(value){
    let s=String(value??'');
    s=s.replace(BRAND_RE,PRODUCT_NAME);
    s=s.replace(/\b(?:build|vers[aã]o|revision|revis[aã]o|release)\s*[:#-]?\s*RT\s*\d+(?:\.\d+)*\b/gi,`Versão ${PUBLIC_VERSION}`);
    s=s.replace(REVISION_RE,'');
    s=s.replace(/^\s*[•·|—–:-]+\s*/,'').replace(/\s*[•·|—–:-]+\s*$/,'');
    s=s.replace(/[ \t]{2,}/g,' ').replace(/\s+([,.;!?])/g,'$1');
    return s;
  }

  function normalizeNode(root){
    if(!root) return;
    if(root.nodeType===Node.TEXT_NODE){
      const parent=root.parentElement;
      if(!parent||SKIP.has(parent.tagName)) return;
      const next=cleanText(root.nodeValue);
      if(next!==root.nodeValue) root.nodeValue=next;
      return;
    }
    if(root.nodeType!==Node.ELEMENT_NODE&&root.nodeType!==Node.DOCUMENT_FRAGMENT_NODE&&root.nodeType!==Node.DOCUMENT_NODE) return;
    if(root.nodeType===Node.ELEMENT_NODE&&SKIP.has(root.tagName)) return;
    const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode(node){const p=node.parentElement;return p&&!SKIP.has(p.tagName)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT}});
    let node;while((node=walker.nextNode())){const next=cleanText(node.nodeValue);if(next!==node.nodeValue)node.nodeValue=next;}
    if(root.querySelectorAll){
      root.querySelectorAll('[title],[aria-label],[placeholder]').forEach(el=>{
        for(const attr of ['title','aria-label','placeholder']) if(el.hasAttribute(attr)){const old=el.getAttribute(attr),next=cleanText(old);if(next!==old)el.setAttribute(attr,next)}
      });
    }
  }

  function apply(){
    if(document.title!==PRODUCT_NAME) document.title=PRODUCT_NAME;
    const meta=document.querySelector('meta[name="application-name"]')||(()=>{const m=document.createElement('meta');m.name='application-name';document.head.appendChild(m);return m})();
    meta.content=PRODUCT_NAME;
    document.documentElement.dataset.productName=PRODUCT_NAME;
    document.documentElement.dataset.publicVersion=PUBLIC_VERSION;
    normalizeNode(document.body);
  }

  let queued=false;
  const schedule=()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;apply()})};
  const observer=new MutationObserver(records=>{for(const r of records)for(const node of r.addedNodes)normalizeNode(node);schedule()});
  if(document.body) observer.observe(document.body,{childList:true,subtree:true,characterData:true});
  else document.addEventListener('DOMContentLoaded',()=>observer.observe(document.body,{childList:true,subtree:true,characterData:true}),{once:true});
  document.addEventListener('DOMContentLoaded',apply,{once:true});
  apply();
})();