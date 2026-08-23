'use strict';
(()=>{
  if(window.__REINO_TRIBAL_ADMIN_RECOVERY_V102__) return;
  window.__REINO_TRIBAL_ADMIN_RECOVERY_V102__=true;
  const SB='https://rlyiwlwzrdgvcwawrnpl.supabase.co';
  const KEY='sb_publishable_S9LtSpLhLKFOU9iSd8b4yQ_EziH1Arr';
  const ENDPOINT=`${SB}/functions/v1/rt-admin-recovery-v102`;
  const esc=s=>String(s??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));
  function msg(text,type=''){
    const global=document.querySelector('#rt18-auth-message');
    if(global){global.textContent=text;global.className=`rt18-auth-message${type?` ${type}`:''}`;}
    const local=document.querySelector('[data-rt102-admin-status]');
    if(local){local.textContent=text;local.dataset.type=type;}
  }
  async function recover(token,password){
    const r=await fetch(ENDPOINT,{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY,'Authorization':`Bearer ${KEY}`},body:JSON.stringify({token,username:'reinos_admin',password})});
    const t=await r.text();let d={};try{d=t?JSON.parse(t):{}}catch{d={error:t}}
    if(!r.ok||!d?.ok)throw new Error(d?.error||`Falha HTTP ${r.status}`);
    return d;
  }
  function enhance(){
    const form=document.querySelector('#rt18-login-form');
    if(!form||document.querySelector('[data-rt102-admin-recovery]'))return;
    const wrap=document.createElement('div');
    wrap.setAttribute('data-rt102-admin-recovery','1');
    wrap.style.marginTop='10px';
    wrap.innerHTML=`<button class="rt18-auth-btn secondary" type="button" data-rt102-open>Recuperar administrador</button><section data-rt102-panel hidden style="margin-top:10px;padding:10px;border:1px solid #9d7a43;border-radius:6px;background:rgba(255,250,232,.8)"><h3 style="margin-top:0">Recuperação administrativa</h3><p class="small">Conta: <b>reinos_admin</b>. Use um código de recuperação de uso único e escolha uma nova senha.</p><form data-rt102-form><label>Código de recuperação<input class="text-input" type="text" name="token" autocomplete="one-time-code" minlength="32" required></label><label>Nova senha<input class="text-input" type="password" name="password" autocomplete="new-password" minlength="12" required></label><label>Confirmar<input class="text-input" type="password" name="confirm" autocomplete="new-password" minlength="12" required></label><button class="rt18-auth-btn" type="submit">Trocar senha do administrador</button></form><p class="small" data-rt102-admin-status></p></section>`;
    form.insertAdjacentElement('afterend',wrap);
    wrap.querySelector('[data-rt102-open]').addEventListener('click',()=>{const p=wrap.querySelector('[data-rt102-panel]');p.hidden=!p.hidden;if(!p.hidden)wrap.querySelector('input[name=token]')?.focus();});
    wrap.querySelector('[data-rt102-form]').addEventListener('submit',async e=>{
      e.preventDefault();const fd=new FormData(e.currentTarget);const token=String(fd.get('token')||'').trim(),p=String(fd.get('password')||''),c=String(fd.get('confirm')||'');
      if(p.length<12)return msg('A nova senha precisa ter pelo menos 12 caracteres.','error');
      if(p!==c)return msg('As senhas não coincidem.','error');
      try{msg('Atualizando a senha administrativa...');await recover(token,p);sessionStorage.removeItem('rt60_admin_token');sessionStorage.removeItem('rt59_admin_token');sessionStorage.removeItem('rt58_admin_token');msg('Senha administrativa atualizada. Entre com reinos_admin e a nova senha.','success');e.currentTarget.reset();}
      catch(err){msg(`Falha na recuperação administrativa: ${err?.message||err}`,'error');}
    });
  }
  const obs=new MutationObserver(enhance);obs.observe(document.documentElement,{childList:true,subtree:true});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',enhance,{once:true});else enhance();
})();
