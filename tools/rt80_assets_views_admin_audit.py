from pathlib import Path
import json, os, re, time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_FULL_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
P={'pass':False,'checks':[],'screenshots':[],'views':[],'admin_tabs':[]}

def rec(name,ok,detail=None):
    ok=bool(ok);P['checks'].append({'name':name,'pass':ok,'detail':detail})
    if not ok: raise AssertionError(f'{name}: {detail}')

def js(d,code,*args): return d.execute_script(code,*args)
def wait(d,code,t=20): WebDriverWait(d,t).until(lambda x: bool(js(x,code)))
def shot(d,name):
    safe=re.sub(r'[^A-Za-z0-9_-]+','_',name)[:80]
    p=OUT/f'{len(P["screenshots"])+1:02d}_{safe}.png';d.save_screenshot(str(p));P['screenshots'].append(p.name)

def click(d,sel):
    WebDriverWait(d,20).until(lambda x: bool(js(x,'return !!document.querySelector(arguments[0])',sel)))
    js(d,'document.querySelector(arguments[0]).click()',sel);time.sleep(.45)

def click_view(d,view):
    ok=js(d,"""
      const v=arguments[0],all=Array.from(document.querySelectorAll(`button[data-view="${CSS.escape(v)}"]`));
      const visible=all.find(b=>{const s=getComputedStyle(b),r=b.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&r.width>0&&r.height>0});
      const b=visible||all[0];if(!b)return false;b.click();return true;
    """,view)
    if not ok: raise AssertionError(f'view button missing: {view}')
    time.sleep(.45)

def start(d):
    d.get(BASE+'?rt80-full-visual=1');wait(d,'return !!document.querySelector("[data-play-offline]")')
    click(d,'[data-play-offline]');wait(d,'return !!document.querySelector("#start-form")')
    js(d,"""
      const f=document.querySelector('#start-form');
      if(f.elements.playerName)f.elements.playerName.value='Visual Full';
      if(f.elements.villageName)f.elements.villageName.value='Aldeia Visual';
      if(f.elements.difficulty)f.elements.difficulty.value='normal';
      if(f.elements.mapRadius)f.elements.mapRadius.value='16';
      if(f.elements.startProfile)f.elements.startProfile.value='balanced';
      f.requestSubmit();
    """)
    wait(d,'return !!window.RT76?.test && !!document.querySelector(".game-shell")',30)

def load_images(d,srcs):
    return d.execute_async_script("""
      const srcs=arguments[0],done=arguments[arguments.length-1];
      Promise.all(srcs.map(src=>new Promise(resolve=>{const i=new Image();i.onload=()=>resolve({src,ok:i.naturalWidth>0&&i.naturalHeight>0,w:i.naturalWidth,h:i.naturalHeight});i.onerror=()=>resolve({src,ok:false,w:0,h:0});i.src=src;}))).then(done);
    """,srcs)

def main():
    o=Options();o.page_load_strategy='eager';o.add_argument('--headless=new');o.add_argument('--disable-gpu');o.add_argument('--no-sandbox');o.add_argument('--window-size=1600,1000');o.add_argument('--disable-dev-shm-usage')
    d=webdriver.Edge(options=o)
    try:
        start(d)
        views=js(d,"return [...new Set(Array.from(document.querySelectorAll('button[data-view]')).map(b=>b.dataset.view).filter(Boolean))]")
        P['views']=views;rec('at least 18 real game views discovered',len(views)>=18,views)
        for view in views:
            click_view(d,view)
            rec(f'view {view} renders non-empty content',js(d,"return (document.querySelector('.content-panel')?.innerText||document.querySelector('.rt22-center')?.innerText||document.querySelector('.game-shell')?.innerText||'').trim().length>15"))
            rec(f'view {view} no desktop body overflow',js(d,'return document.documentElement.scrollWidth<=window.innerWidth+12'))
            shot(d,f'VIEW_{view}')

        hero=js(d,"""
          const items=RT76.test.heroItems();return Object.keys(items).map(id=>({id,slot:items[id].slot,src:RT76.test.getHeroItemArt(id)}));
        """)
        P['hero_items']=hero
        rec('16 Paladin items are defined',len(hero)==16,len(hero))
        rec('16 Paladin items have 16 individual art paths',len({x['src'] for x in hero if x['src']})==16,[x for x in hero if not x['src']])
        hero_load=load_images(d,[x['src'] for x in hero]);P['hero_image_load']=hero_load
        rec('all Paladin item arts load',all(x['ok'] for x in hero_load),[x for x in hero_load if not x['ok']])
        js(d,"""
          const h=RT76.test.getState().player.hero;RT76.test.ensureHeroStoryState(h);const items=RT76.test.heroItems();h.story.equipment={};
          for(const slot of ['weapon','relic','mount','trinket']){const id=Object.keys(items).find(k=>items[k].slot===slot);if(id)h.story.equipment[slot]=id;}
          RT76.test.setView('hero');
        """);time.sleep(.6)
        rec('Paladin composite renders base plus four item layers',js(d,"return document.querySelectorAll('.rt28-hero-loadout img').length>=5"),js(d,"return Array.from(document.querySelectorAll('.rt28-hero-loadout img')).map(x=>x.className)"))
        shot(d,'PALADIN_FOUR_EQUIPMENT_LAYERS')

        unit_data=js(d,"""
          const keys=['spear','sword','axe','archer','spy','light','marcher','heavy','ram','catapult'],levels=[0,1,4,7],v=RT76.test.getActiveVillage();v.unitResearch=v.unitResearch||{};RT76.test.getState().settings.researchSystem='ten';
          return keys.map(key=>({key,arts:levels.map(level=>{v.unitResearch[key]=level;return getUnitArt(key,v)})}));
        """)
        P['unit_stages']=unit_data
        rec('10 research-evolving troop families',len(unit_data)==10,len(unit_data))
        rec('every troop has four distinct stage arts',all(len(set(x['arts']))==4 for x in unit_data),[x for x in unit_data if len(set(x['arts']))!=4])
        unit_load=load_images(d,[src for x in unit_data for src in x['arts']]);P['unit_image_load']=unit_load
        rec('all 40 troop stage arts load',all(x['ok'] for x in unit_load),[x for x in unit_load if not x['ok']])
        vscript="const v=RT76.test.getActiveVillage();v.unitResearch=v.unitResearch||{};RT76.test.getState().settings.researchSystem='ten';for(const k of ['spear','sword','axe','archer','spy','light','marcher','heavy','ram','catapult'])v.unitResearch[k]=arguments[0];RT76.test.setView('recruit');"
        js(d,vscript,0);time.sleep(.5);shot(d,'TROOPS_VISUAL_STAGE_0')
        js(d,vscript,7);time.sleep(.5);shot(d,'TROOPS_VISUAL_STAGE_3')

        mock={'version':80,'generated_at':'2026-08-19T18:00:00Z','worlds':[{'id':'w1','name':'Mundo Visual','settings':{},'max_players':50,'season_number':1,'status':'open','is_active':True}], 'players':[{'world_id':'w1','user_id':'u1','player_name':'Jogador Visual','email':'visual@local','last_seen_at':'2026-08-19T18:00:00Z'}], 'villages':[{'id':'v1','world_id':'w1','owner_user_id':'u1','owner_kind':'player','name':'Aldeia Visual','x':500,'y':500,'points':100,'resources':{'wood':1000,'clay':1000,'iron':1000},'buildings':{},'units':{}}], 'nodes':[],'events':[],'monsters':[],'eventTemplates':[],'monsterTemplates':[],'commands':[],'attacks':[],'tribes':[],'tribeMembers':[],'offers':[],'messages':[],'reports':[],'entitlements':[],'rtWorldEvents':[],'eventProgress':[],'eventRewards':[],'auditLog':[],'seasons':[],'ratings':[],'matches':[],'adminSessions':[],'adminAccounts':[],'monsterHits':[],'worldStats':[{'world_id':'w1','players':1,'online':1,'villages':1,'nodes':0,'monsters':0,'events':0,'commands':0,'tribes':0,'offers':0}],'dbCounts':{'players':1,'villages':1}}
        admin_result=d.execute_async_script("""
          const data=arguments[0],done=arguments[arguments.length-1];
          try{RTADMIN.token='ci-visual';RTADMIN.info={username:'visual_admin',role:'superadmin'};adminSupportRequest=async()=>({supports:[]});renderIntegratedAdmin(data,true).then(()=>done({ok:true})).catch(e=>done({ok:false,error:String(e)}));}catch(e){done({ok:false,error:String(e)})}
        """,mock)
        rec('real admin renderer opens with visual mock',admin_result.get('ok'),admin_result)
        time.sleep(.6);rec('RT80 admin mode detected',js(d,"return document.body.classList.contains('rt80-admin-mode')"))
        rec('admin branding cleaned to RT80',js(d,"return !/RT79/.test(document.querySelector('.rt60-admin-top')?.innerText||'')"))
        tabs=js(d,"return Array.from(document.querySelectorAll('.rt60-admin-nav button[data-admin-tab]')).map(b=>b.dataset.adminTab)");P['admin_tabs']=tabs
        rec('admin exposes at least 12 operational tabs',len(tabs)>=12,tabs)
        for tab in tabs:
            click(d,f'.rt60-admin-nav button[data-admin-tab="{tab}"]')
            rec(f'admin tab {tab} visible',js(d,"return !!document.querySelector(arguments[0]) && !document.querySelector(arguments[0]).classList.contains('hidden')",f'[data-admin-panel="{tab}"]'))
            rec(f'admin tab {tab} no desktop overflow',js(d,'return document.documentElement.scrollWidth<=window.innerWidth+12'))
            shot(d,f'ADMIN_{tab}')
        d.set_window_size(430,932);time.sleep(.7)
        rec('admin mobile no body overflow',js(d,'return document.documentElement.scrollWidth<=window.innerWidth+12'))
        shot(d,'ADMIN_MOBILE')
        P['pass']=True
    except Exception as e:
        P['error']=repr(e)
        try: shot(d,'FAILURE')
        except Exception: pass
        raise
    finally:
        try:P['console']=d.get_log('browser')
        except Exception:P['console']=[]
        (OUT/'PROVA_RT80_FULL_VISUAL.json').write_text(json.dumps(P,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()

if __name__=='__main__':main()
