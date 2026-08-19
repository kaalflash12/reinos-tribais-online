from pathlib import Path
import json, os, time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[],'page_audit':[]}


def check(d,name,js,timeout=25):
    WebDriverWait(d,timeout).until(lambda x:x.execute_script(js))
    ok=bool(d.execute_script(js))
    proof['checks'].append({'name':name,'pass':ok})
    if not ok:
        raise AssertionError(name)


def shot(d,name):
    path=OUT/f'{len(proof["screenshots"])+1:02d}_{name}.png'
    d.save_screenshot(str(path))
    proof['screenshots'].append(path.name)


def click(d,selector):
    WebDriverWait(d,20).until(lambda x:x.execute_script("return !!document.querySelector(arguments[0])",selector))
    d.execute_script("document.querySelector(arguments[0]).click()",selector)
    time.sleep(.55)


def audit_page(d,view,label=None):
    click(d,f'[data-view="{view}"]')
    time.sleep(.35)
    check(d,f'{view}: page header visible','''
      const h=document.querySelector('.rt68-page-header');
      const r=h?.getBoundingClientRect();
      return !!h && getComputedStyle(h).display!=='none' && r.width>300 && r.height>35;
    ''')
    check(d,f'{view}: content visible','''
      const p=document.querySelector('.content-panel');
      const r=p?.getBoundingClientRect();
      return !!p && getComputedStyle(p).display!=='none' && r.width>300 && r.height>120;
    ''')
    check(d,f'{view}: requested view tracked',f'return document.body.dataset.rt80View==="{view}" || document.body.dataset.rt80RequestedView==="{view}"')
    check(d,f'{view}: no duplicate direct panel title','''
      const t=document.querySelector('.content-panel > h1.panel-title');
      return !t || getComputedStyle(t).display==='none';
    ''')
    check(d,f'{view}: desktop no body overflow','return document.documentElement.scrollWidth <= window.innerWidth + 16')
    meta=d.execute_script('''
      const h=document.querySelector('.rt68-page-header h1');
      const p=document.querySelector('.content-panel');
      return {title:(h?.textContent||'').trim(),height:Math.round(p?.getBoundingClientRect().height||0),scrollWidth:document.documentElement.scrollWidth,viewport:window.innerWidth};
    ''')
    proof['page_audit'].append({'view':view,**meta})
    shot(d,label or f'PAGE_{view.upper()}_RT80')


def extra_quality_checks(d,view):
    if view=='inventory':
        check(d,'inventory: cards use dark game surface','''
          const c=document.querySelector('.item-card');
          if(!c)return false;
          const s=getComputedStyle(c);
          return !s.backgroundImage.includes('255, 244, 210') && !s.backgroundImage.includes('228, 201, 140') && parseFloat(s.minHeight)>=150;
        ''')
        check(d,'inventory: item text has light foreground','''
          const c=document.querySelector('.item-card');
          const h=c?.querySelector('h3');
          return !!h && getComputedStyle(c).color!=='rgb(42, 26, 15)' && getComputedStyle(h).color!=='rgb(42, 26, 15)';
        ''')
    elif view=='premium':
        check(d,'premium: benefits no longer parchment cards','''
          const a=document.querySelector('.rt13-feature-grid > article');
          if(!a)return false;
          const s=getComputedStyle(a);
          return !s.backgroundImage.includes('255, 244, 210') && getComputedStyle(a.querySelector('b')||a).color!=='rgb(42, 26, 15)';
        ''')
    elif view=='events':
        check(d,'events: operational header separated','''
          const h=document.querySelector('.rt60-events-screen > .panel-header');
          const span=h?.querySelector(':scope > span');
          const small=span?.querySelector('small');
          const b=span?.querySelector('b');
          return !!h && getComputedStyle(h).display==='flex' && !!b && !!small && getComputedStyle(small).display==='block';
        ''')
        check(d,'events: refresh button matches game UI','''
          const b=document.querySelector('.rt60-events-screen > .panel-header .button');
          if(!b)return false;
          const s=getComputedStyle(b);
          return s.backgroundColor!=='rgb(255, 255, 255)' && s.color!=='rgb(0, 0, 0)';
        ''')
    elif view in ('manager','settings'):
        check(d,f'{view}: no visible legacy RT76/RT79 branding','''
          const p=document.querySelector('.content-panel');
          const t=p?.innerText||'';
          return !/\bRT76\b|\bRT79(?:\.1)?\b|Versão\s+79\b/.test(t);
        ''')


def main():
    opts=Options();opts.page_load_strategy='eager'
    opts.add_argument('--headless=new');opts.add_argument('--disable-gpu');opts.add_argument('--no-sandbox')
    opts.add_argument('--window-size=1600,1000');opts.add_argument('--disable-dev-shm-usage')
    opts.add_argument('--disable-features=BlockInsecurePrivateNetworkRequests')
    d=webdriver.Edge(options=opts)
    try:
        d.get(BASE+'?rt80-visual=1')
        check(d,'body ready','return !!document.body')
        check(d,'RT80 visual loaded','return document.body.classList.contains("rt80-visual-ready")')
        check(d,'entry screen exists','return !!document.querySelector(".rt55-entry") && !!document.querySelector("[data-play-offline]")')
        check(d,'RT80 entry branding','return (document.querySelector(".rt55-kicker")?.textContent||"").includes("RT78") || getComputedStyle(document.querySelector(".rt55-kicker"),"::after").content.includes("RT80")')
        shot(d,'START_SCREEN_RT80')

        click(d,'[data-play-offline]')
        WebDriverWait(d,15).until(lambda x:x.execute_script("return !!document.querySelector('#start-form')"))
        d.execute_script("""
          const f=document.querySelector('#start-form');
          if(f.elements.playerName) f.elements.playerName.value='Auditoria RT80';
          if(f.elements.villageName) f.elements.villageName.value='Aldeia RT80';
          if(f.elements.difficulty) f.elements.difficulty.value='normal';
          if(f.elements.mapRadius) f.elements.mapRadius.value='16';
          if(f.elements.startProfile) f.elements.startProfile.value='military';
          f.requestSubmit();
        """)
        check(d,'game shell','return !!document.querySelector(".game-shell")')
        check(d,'village scene','return !!document.querySelector(".village-scene")')
        check(d,'village mode','return document.body.classList.contains("rt80-village-mode")')
        check(d,'19 building hitboxes','return document.querySelectorAll(".village-scene .rt60-village-hitbox").length>=19')
        check(d,'RT80 village toolbar','return !!document.querySelector(".rt80-village-toolbar")')
        check(d,'no fake roads','return !document.querySelector(".rt79-road-net")')
        check(d,'no fake wall perimeter','return !document.querySelector(".rt79-wall-perimeter")')
        shot(d,'VILLAGE_RT80')

        click(d,'[data-rt79-vcat="military"]')
        check(d,'building category focus','return document.querySelectorAll(".village-scene .rt79-focus").length>0 && document.querySelectorAll(".village-scene .rt79-dim").length>0')
        shot(d,'VILLAGE_MILITARY_FOCUS')

        click(d,'[data-view="map"]')
        check(d,'map mode','return document.body.classList.contains("rt80-map-mode")')
        check(d,'map toolbar','return !!document.querySelector(".rt80-map-toolbar")')
        check(d,'map toolbar is controls only','''
          const bar=document.querySelector('.rt80-map-toolbar');
          const title=bar?.querySelector('strong');
          const hint=bar?.querySelector(':scope > span');
          return !!bar && (!title || getComputedStyle(title).display==='none') && (!hint || getComputedStyle(hint).display==='none');
        ''')
        shot(d,'MAP_RT80')

        audit_page(d,'buildings','BUILDINGS_PAGE_RT80')
        check(d,'single building category spans full row','''
          const list=document.querySelector('[data-building-category="admin"] .rt64-building-list');
          const row=list?.querySelector('.rt64-building-row:only-child');
          return !!row && getComputedStyle(row).gridColumnEnd==='-1';
        ''')
        check(d,'buildings duplicate inner title hidden','''
          const t=document.querySelector('.rt64-building-overview-head .panel-title');
          return !!t && getComputedStyle(t).display==='none';
        ''')
        check(d,'buildings quick nav no longer sticky','''
          const q=document.querySelector('.rt64-building-overview-head ~ .rt64-building-quicknav');
          return !!q && getComputedStyle(q).position!=='sticky';
        ''')

        audit_page(d,'research','RESEARCH_PAGE_RT80')
        audit_page(d,'market','MARKET_PAGE_RT80')
        check(d,'market ledger uses dark data rows','''
          const td=document.querySelector('.data-table td');
          if(!td)return false;
          const c=getComputedStyle(td).backgroundColor;
          return c==='rgb(20, 24, 17)' || c==='rgb(16, 20, 15)' || c.includes('20, 24, 17');
        ''')
        audit_page(d,'hero','PALADIN_PAGE_RT80')
        check(d,'paladin hero banner visible','''
          const h=document.querySelector('.rt19-paladin-hero');
          const r=h?.getBoundingClientRect();
          return !!h && getComputedStyle(h).display!=='none' && r.width>500 && r.height>180;
        ''')

        secondary=[
          ('systems','SYSTEMS'),('recruit','RECRUIT'),('rally','RALLY'),('academy','ACADEMY'),
          ('arsenal','ARSENAL'),('commands','COMMANDS'),('missions','MISSIONS'),('reports','REPORTS'),
          ('messages','MESSAGES'),('inventory','INVENTORY'),('premium','PREMIUM'),('manager','MANAGER'),
          ('flags','FLAGS'),('ranking','RANKING'),('tribe','TRIBE'),('help','HELP'),('settings','SETTINGS'),
          ('events','EVENTS'),('ranked','RANKED')
        ]
        for view,label in secondary:
            audit_page(d,view,f'PAGE_{label}_RT80')
            extra_quality_checks(d,view)

        d.set_window_size(430,932);time.sleep(.8)
        click(d,'[data-view="overview"]');time.sleep(.7)
        check(d,'mobile no horizontal body overflow','return document.documentElement.scrollWidth <= window.innerWidth + 8')
        check(d,'legacy RT68 mobile nav hidden','''
          const a=document.querySelector('.rt68-game-nav');
          const b=document.querySelector('.rt68-game-nav-scroll');
          return (!a || getComputedStyle(a).display==='none') && (!b || getComputedStyle(b).display==='none');
        ''')
        check(d,'RT22 mobile nav is grid','return !!document.querySelector(".rt22-navicons") && getComputedStyle(document.querySelector(".rt22-navicons")).display==="grid"')
        check(d,'RT22 mobile nav has five visible actions','''
          const buttons=Array.from(document.querySelectorAll('.rt22-navicons button'));
          const visible=buttons.filter(b=>getComputedStyle(b).display!=='none' && b.getBoundingClientRect().width>0);
          const views=visible.map(b=>b.dataset.view).sort();
          return visible.length===5 && ['buildings','commands','hero','map','market'].every(v=>views.includes(v));
        ''')
        proof['mobile_navs']=d.execute_script("""
          return Array.from(document.querySelectorAll('nav,[class*="nav"],[class*="menu"],[class*="toolbar"]')).map((n,i)=>{
            const r=n.getBoundingClientRect(),s=getComputedStyle(n);
            return {i,tag:n.tagName,cls:n.className||'',id:n.id||'',display:s.display,position:s.position,x:Math.round(r.x),y:Math.round(r.y),w:Math.round(r.width),h:Math.round(r.height),text:(n.innerText||'').replace(/\\s+/g,' ').trim().slice(0,180)};
          }).filter(x=>x.display!=='none'&&x.w>200&&x.h>20);
        """)
        shot(d,'MOBILE_RT80')
        proof['pass']=True
    except Exception as e:
        proof['error']=repr(e)
        try: shot(d,'FAILURE')
        except Exception: pass
        raise
    finally:
        try: proof['console']=d.get_log('browser')
        except Exception: proof['console']=[]
        (OUT/'PROVA_RT80_VISUAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()

if __name__=='__main__': main()
