from pathlib import Path

FILES=[Path('index.html'),Path('JOGAR_REINOS_TRIBAIS.html')]
OLD="""function rt67RenderPageIntro(tab=RTADMIN?.ui?.tab||'overview'){
  const main=document.querySelector('.rt60-admin-main');if(!main)return;
  let el=main.querySelector('.rt67-page-intro');if(!el){el=document.createElement('section');el.className='rt67-page-intro';main.prepend(el)}
  const [title,desc]=RT67_PAGE_HELP[tab]||['Administração','Controle operacional do servidor.'];
  el.innerHTML=`<div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(desc)}</p></div><span class=\"rt67-help-pill\">Modo guiado • sem códigos de cabeça</span>`;
}"""
NEW="""function rt67RenderPageIntro(tab=RTADMIN?.ui?.tab||'overview'){
  const main=document.querySelector('.rt60-admin-main');if(!main)return;
  let el=main.querySelector('.rt67-page-intro');if(!el){el=document.createElement('section');el.className='rt67-page-intro';main.prepend(el)}
  const [title,desc]=RT67_PAGE_HELP[tab]||['Administração','Controle operacional do servidor.'];
  const html=`<div><h2>${escapeHtml(title)}</h2><p>${escapeHtml(desc)}</p></div><span class=\"rt67-help-pill\">Modo guiado • sem códigos de cabeça</span>`;
  if(el.innerHTML!==html)el.innerHTML=html;
}"""

def main():
    for path in FILES:
        text=path.read_text(encoding='utf-8')
        if OLD not in text:
            if NEW in text:
                print(path,'already patched')
                continue
            raise SystemExit(f'anchor missing in {path}')
        path.write_text(text.replace(OLD,NEW,1),encoding='utf-8')
        print(path,'patched')

if __name__=='__main__':main()
