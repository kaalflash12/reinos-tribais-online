'use strict';
(()=>{
  if(window.__RT85_AUTH_BRIDGE__) return;
  window.__RT85_AUTH_BRIDGE__=true;
  const ORIGINAL_FETCH=window.fetch.bind(window);
  const SUPABASE_ORIGIN='https://rlyiwlwzrdgvcwawrnpl.supabase.co';
  const APIKEY='sb_publishable_S9LtSpLhLKFOU9iSd8b4yQ_EziH1Arr';
  const SESSION_KEY='reinos_tribais_supabase_session_v60_browser';
  const AUTO_KEY='rt85_auth_autocontinue';

  const parseBody=body=>{try{return typeof body==='string'?JSON.parse(body):body||{}}catch{return {}}};
  const urlOf=input=>typeof input==='string'?input:(input?.url||'');
  const broker=async(action,payload={})=>{
    const r=await ORIGINAL_FETCH(`${SUPABASE_ORIGIN}/functions/v1/rt-login-v85`,{
      method:'POST',headers:{apikey:APIKEY,'Content-Type':'application/json'},body:JSON.stringify({action,...payload}),cache:'no-store'
    });
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null}catch{data={error:text||`HTTP ${r.status}`}}
    if(!r.ok)throw new Error(data?.error||data?.message||`HTTP ${r.status}`);
    return data;
  };

  window.fetch=async function(input,init={}){
    const url=urlOf(input);
    if(url.startsWith(`${SUPABASE_ORIGIN}/auth/v1/token?grant_type=password`) && String(init?.method||'GET').toUpperCase()==='POST'){
      const body=parseBody(init?.body);
      const identifier=String(body?.email||body?.identifier||'').trim();
      const password=String(body?.password||'');
      try{
        const r=await ORIGINAL_FETCH(`${SUPABASE_ORIGIN}/functions/v1/rt-login-v85`,{
          method:'POST',headers:{apikey:APIKEY,'Content-Type':'application/json'},body:JSON.stringify({action:'password_login',identifier,password}),cache:'no-store'
        });
        if(r.status<500 || !identifier.includes('@')) return r;
      }catch(e){ if(!identifier.includes('@')) throw e; }
      return ORIGINAL_FETCH(input,init);
    }
    return ORIGINAL_FETCH(input,init);
  };

  function msg(text,type=''){
    const el=document.querySelector('#rt18-auth-message');
    if(!el)return;
    el.className=`rt18-auth-message${type?` ${type}`:''}`;
    el.textContent=text;
  }

  function enhanceAuth(){
    const form=document.querySelector('#rt18-login-form');
    if(!form||form.dataset.rt85Enhanced==='1')return;
    form.dataset.rt85Enhanced='1';
    const actions=form.querySelector('.rt59-inline')||form;
    const btn=document.createElement('button');
    btn.type='button';btn.className='rt18-auth-btn secondary';btn.dataset.rt85Code='1';btn.textContent='Entrar por código';
    actions.prepend(btn);
    const panel=document.createElement('section');
    panel.className='rt64-recovery-code-panel';panel.dataset.rt85CodePanel='1';panel.hidden=true;
    panel.innerHTML=`<h3>🔑 Entrar por código</h3><form data-rt85-code-form><div class="rt64-recovery-code-grid"><label>E-mail ou usuário<input class="text-input" name="identifier" autocomplete="username" required></label><label>Código<input class="text-input" name="code" inputmode="numeric" minlength="6" maxlength="8" autocomplete="one-time-code" required placeholder="000000"></label></div><div class="rt59-inline" style="margin-top:9px"><button class="rt18-auth-btn" type="submit">Validar e entrar</button><button class="rt18-auth-btn secondary" type="button" data-rt85-resend>Reenviar</button></div><p class="rt64-recovery-help">RT85: funciona com e-mail ou nome de usuário ligado à conta.</p></form>`;
    form.insertAdjacentElement('afterend',panel);
  }

  async function requestCode(identifier){
    await broker('request_otp',{identifier});
    msg('Se a conta existir, o código/link de acesso foi enviado.','success');
  }

  document.addEventListener('click',async e=>{
    const open=e.target.closest?.('[data-rt85-code]');
    if(open){
      const panel=document.querySelector('[data-rt85-code-panel]');const src=document.querySelector('#rt18-login-form input[name="email"]');const dst=panel?.querySelector('input[name="identifier"]');
      if(panel)panel.hidden=false;if(dst&&src?.value)dst.value=src.value.trim();
      const id=String(dst?.value||'').trim();if(id.length>=3){try{msg('Solicitando código de acesso...');await requestCode(id)}catch(err){msg(`Código de acesso: ${err.message||err}`,'error')}}
      return;
    }
    const resend=e.target.closest?.('[data-rt85-resend]');
    if(resend){const id=String(document.querySelector('[data-rt85-code-form] input[name="identifier"]')?.value||'').trim();if(id.length<3)return msg('Informe e-mail ou usuário.','error');try{msg('Reenviando código...');await requestCode(id)}catch(err){msg(`Código de acesso: ${err.message||err}`,'error')}return;}
  },true);

  document.addEventListener('submit',async e=>{
    const form=e.target.closest?.('[data-rt85-code-form]');if(!form)return;
    e.preventDefault();e.stopImmediatePropagation();
    const fd=new FormData(form),identifier=String(fd.get('identifier')||'').trim(),token=String(fd.get('code')||'').trim();
    if(identifier.length<3||token.length<6)return msg('Informe e-mail/usuário e código.','error');
    try{
      msg('Validando código de acesso...');
      const session=await broker('verify_otp',{identifier,token});
      if(!session?.access_token||!session?.user?.id)throw new Error('Sessão não recebida.');
      sessionStorage.setItem(SESSION_KEY,JSON.stringify(session));sessionStorage.setItem(AUTO_KEY,'1');location.reload();
    }catch(err){msg(`Não foi possível entrar por código: ${err.message||err}`,'error')}
  },true);

  function autoContinue(){
    enhanceAuth();
    if(sessionStorage.getItem(AUTO_KEY)==='1'){
      const b=document.querySelector('[data-cloud-continue]');
      if(b){sessionStorage.removeItem(AUTO_KEY);b.click();}
    }
  }
  new MutationObserver(autoContinue).observe(document.documentElement,{childList:true,subtree:true});
  setInterval(autoContinue,1200);autoContinue();
  window.RT85Auth={version:85,health:()=>broker('health')};
})();