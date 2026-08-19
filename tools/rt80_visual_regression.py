from pathlib import Path
import json, os, time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[],'building_tiers':{}}

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

def audit_building_tier(d,tier):
    d.execute_script('window.RT76.test.setAllBuildingTier(arguments[0]);',tier)
    time.sleep(.7)
    check(d,f'tier {tier} has 19 rendered building arts','return document.querySelectorAll(".village-scene .rt75-building-art[data-village-building]").length===19')
    check(d,f'tier {tier} has 19 interactive lots','return document.querySelectorAll(".village-scene .rt60-village-hitbox").length===19')
    check(d,f'tier {tier} target boxes stay inside scene','''
      return Array.from(document.querySelectorAll('.village-scene .rt75-building-art[data-target-bbox]')).every(img=>{
        const b=(img.dataset.targetBbox||'').split(',').map(Number);
        return b.length===4 && b.every(Number.isFinite) && b[0]>=0 && b[1]>=0 && b[2]<=1671 && b[3]<=941 && b[2]>b[0] && b[3]>b[1];
      });
    ''')
    rows=d.execute_script('''
      const scene=document.querySelector('.village-scene').getBoundingClientRect();
      return Array.from(document.querySelectorAll('.village-scene .rt75-building-art[data-village-building]')).map(img=>{
        const r=img.getBoundingClientRect();
        return {key:img.dataset.villageBuilding,tier:Number(img.dataset.villageTier||0),src:(img.getAttribute('src')||''),target:img.dataset.targetBbox||'',alpha:img.dataset.alphaBbox||'',x:+((r.left-scene.left)/scene.width*100).toFixed(2),y:+((r.top-scene.top)/scene.height*100).toFixed(2),w:+(r.width/scene.width*100).toFixed(2),h:+(r.height/scene.height*100).toFixed(2)};
      }).sort((a,b)=>a.key.localeCompare(b.key));
    ''')
    proof['building_tiers'][str(tier)]=rows
    shot(d,f'VILLAGE_ALL_BUILDINGS_TIER_{tier}')

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
          if(f.elements.startProfile) f.elements.startProfile.value='balanced';
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
        d.set_window_size(1600,1000);click(d,'[data-view="overview"]')
        d.execute_script("""
          const s=RT76.test.getState(),v=RT76.test.getActiveVillage();
          if(s.player?.research) s.player.research.completed=[];
          v.unitResearch={};
          RT76.test.render();
        """)
        for tier in (1,2,3,4): audit_building_tier(d,tier)
        keys=sorted({r['key'] for rows in proof['building_tiers'].values() for r in rows})
        assert len(keys)==19, f'expected 19 building keys, got {len(keys)}'
        failures=[]
        for key in keys:
            seq=[]
            for tier in ('1','2','3','4'):
                row=next((r for r in proof['building_tiers'][tier] if r['key']==key),None)
                if row: seq.append(row['src'])
            if len(seq)!=4 or len(set(seq))!=4: failures.append({'key':key,'srcs':seq})
        proof['building_evolution_failures']=failures
        proof['checks'].append({'name':'all 19 buildings use four distinct level-evolution arts','pass':not failures})
        if failures: raise AssertionError(f'building evolution missing: {failures}')
        d.execute_script("""
          RT76.test.setAllBuildingTier(1);
          const v=RT76.test.getActiveVillage();v.unitResearch={axe:2};RT76.test.render();
        """);time.sleep(.5)
        check(d,'military research advances barracks stable garage and smith appearance','''
          const v=RT76.test.getActiveVillage();
          return ['barracks','stable','garage','smith'].every(k=>RT76.test.getBuildingVisual(v,k).tier>=2);
        ''')
        shot(d,'VILLAGE_MILITARY_RESEARCH_VISUAL_ADVANCE')
        for view,name in [('map','MAP_RT80'),('buildings','BUILDINGS_PAGE_RT80'),('research','RESEARCH_PAGE_RT80'),('market','MARKET_PAGE_RT80'),('hero','PALADIN_PAGE_RT80')]:
            click(d,f'[data-view="{view}"]')
            time.sleep(.6)
            if view=='map':
                check(d,'map mode','return document.body.classList.contains("rt80-map-mode")')
                check(d,'map toolbar','return !!document.querySelector(".rt80-map-toolbar")')
            else:
                check(d,f'{view} content visible','return !!document.querySelector(".content-panel")')
            if view=='buildings':
                check(d,'single building category spans full row','''
                  const list=document.querySelector('[data-building-category="admin"] .rt64-building-list');
                  const row=list?.querySelector('.rt64-building-row:only-child');
                  return !!row && getComputedStyle(row).gridColumnEnd==='-1';
                ''')
            shot(d,name)
        d.set_window_size(430,932);time.sleep(.8)
        click(d,'[data-view="overview"]');time.sleep(.5)
        check(d,'mobile no horizontal body overflow','return document.documentElement.scrollWidth <= window.innerWidth + 8')
        check(d,'legacy RT68 mobile nav hidden','return !document.querySelector(".rt68-game-nav") || getComputedStyle(document.querySelector(".rt68-game-nav")).display==="none"')
        check(d,'RT22 mobile nav is grid','return !!document.querySelector(".rt22-navicons") && getComputedStyle(document.querySelector(".rt22-navicons")).display==="grid"')
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
