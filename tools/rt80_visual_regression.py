from pathlib import Path
import json, os, time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[]}

def check(d,name,js,timeout=25):
    WebDriverWait(d,timeout).until(lambda x:x.execute_script(js))
    ok=bool(d.execute_script(js))
    proof['checks'].append({'name':name,'pass':ok})
    if not ok: raise AssertionError(name)

def shot(d,name):
    path=OUT/f'{len(proof["screenshots"])+1:02d}_{name}.png'
    d.save_screenshot(str(path));proof['screenshots'].append(path.name)

def click(d,selector):
    WebDriverWait(d,20).until(lambda x:x.execute_script("return !!document.querySelector(arguments[0])",selector))
    d.execute_script("document.querySelector(arguments[0]).click()",selector)
    time.sleep(.8)

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
        check(d,'start screen exists','return !!document.querySelector(".start-screen")')
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
        for view,name in [('map','MAP_RT80'),('buildings','BUILDINGS_PAGE_RT80'),('research','RESEARCH_PAGE_RT80'),('market','MARKET_PAGE_RT80'),('hero','PALADIN_PAGE_RT80')]:
            click(d,f'[data-view="{view}"]')
            time.sleep(.6)
            if view=='map':
                check(d,'map mode','return document.body.classList.contains("rt80-map-mode")')
                check(d,'map toolbar','return !!document.querySelector(".rt80-map-toolbar")')
            else:
                check(d,f'{view} content visible','return !!document.querySelector(".content-panel")')
            shot(d,name)
        d.set_window_size(430,932);time.sleep(.8)
        click(d,'[data-view="overview"]');time.sleep(.5)
        check(d,'mobile no horizontal body overflow','return document.documentElement.scrollWidth <= window.innerWidth + 8')
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
