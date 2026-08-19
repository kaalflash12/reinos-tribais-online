from pathlib import Path
import re

FILES=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]

PATCHES=[
("""function rt67RenderPageIntro(tab=RTADMIN?.ui?.tab||'overview'){
  const main=document.querySelector('.rt60-admin-main');if(!main)return;
  let el=main.querySelector('.rt67-page-intro');if(!el){el=document.createElement('section');el.className='rt67-page-intro';main.prepend(el)}
  const [title,desc]=RT67_PAGE_HELP[tab]||['Administração','Controle operacional do servidor.'];
  el.innerHTML=`<div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(desc)}</p></div><span class=\"rt67-help-pill\">Modo guiado • sem códigos de cabeça</span>`;
}""",
"""function rt67RenderPageIntro(tab=RTADMIN?.ui?.tab||'overview'){
  const main=document.querySelector('.rt60-admin-main');if(!main)return;
  let el=main.querySelector('.rt67-page-intro');if(!el){el=document.createElement('section');el.className='rt67-page-intro';main.prepend(el)}
  const [title,desc]=RT67_PAGE_HELP[tab]||['Administração','Controle operacional do servidor.'];
  const html=`<div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(desc)}</p></div><span class=\"rt67-help-pill\">Modo guiado • sem códigos de cabeça</span>`;
  if(el.innerHTML!==html)el.innerHTML=html;
}"""),
("""function rt67EnhanceAdminChrome(){if(!document.querySelector('.rt60-admin-shell'))return;rt67GroupAdminNav();rt67RenderPageIntro();const out=document.querySelector('[data-admin-logout]');if(out){out.textContent='Sair do admin';out.classList.add('rt67-admin-logout');out.title='Encerra esta sessão administrativa neste navegador e no servidor.'}}""",
"""function rt67EnhanceAdminChrome(){if(!document.querySelector('.rt60-admin-shell'))return;rt67GroupAdminNav();rt67RenderPageIntro();const out=document.querySelector('[data-admin-logout]');if(out){if(out.textContent!=='Sair do admin')out.textContent='Sair do admin';if(!out.classList.contains('rt67-admin-logout'))out.classList.add('rt67-admin-logout');const title='Encerra esta sessão administrativa neste navegador e no servidor.';if(out.title!==title)out.title=title}}""")
]

REWARD_RE=re.compile(
    r"(function rt67UpdateRewardForm\(\)\{.*?const p=f\.querySelector\('\[data-rt67-reward-preview\]'\);)if\(p\)p\.innerHTML=(`.*?</small>`)(\})",
    re.S,
)

def patch_reward_preview(text:str)->tuple[str,bool]:
    if "if(p&&p.innerHTML!==html)p.innerHTML=html" in text:
        return text,False
    m=REWARD_RE.search(text)
    if not m:
        raise SystemExit('rt67UpdateRewardForm idempotence anchor missing')
    repl=m.group(1)+"const html="+m.group(2)+";if(p&&p.innerHTML!==html)p.innerHTML=html"+m.group(3)
    return text[:m.start()]+repl+text[m.end():],True

def main():
    for path in FILES:
        text=path.read_text(encoding='utf-8')
        changed=False
        for old,new in PATCHES:
            if new in text:
                continue
            if old not in text:
                raise SystemExit(f'anchor missing in {path}: {old[:80]}')
            text=text.replace(old,new,1);changed=True
        text,reward_changed=patch_reward_preview(text)
        changed=changed or reward_changed
        path.write_text(text,encoding='utf-8')
        print(path,'patched' if changed else 'already patched')

if __name__=='__main__':main()
