import os,time,json
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import TimeoutException
import rt79_browser_regression as r

URL=os.environ.get('RT79_TEST_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT79_BROWSER_REGRESSION'
OUT.mkdir(parents=True,exist_ok=True)
manifest=[]

def rec(name,ok=True,detail=''):
    manifest.append({'name':name,'pass':bool(ok),'detail':detail})
    if not ok: raise AssertionError(f'{name}: {detail}')

def shot(d,name):
    p=OUT/f'{len([x for x in manifest if x.get("file")])+1:03d}_{name}.png'
    d.save_screenshot(str(p));manifest.append({'name':name,'file':p.name})

def nav(d,url):
    try:d.get(url)
    except TimeoutException:pass
    WebDriverWait(d,20).until(lambda x:x.execute_script("return !!document.body"))
    WebDriverWait(d,20).until(lambda x:x.execute_script("return !!window.__RT79_STRATEGY_SUITE__"))
    time.sleep(.8)

def click(d,sel):
    ok=d.execute_script("const e=document.querySelector(arguments[0]);if(!e)return false;e.click();return true",sel)
    if not ok:raise AssertionError('missing '+sel)
    time.sleep(.25)

def start_game(d):
    nav(d,URL+'?rt79-chrome-full=1')
    d.execute_script("Object.keys(localStorage).filter(k=>k.startsWith('reinos_tribais_ptbr_save_')).forEach(k=>localStorage.removeItem(k));")
    rec('rt79_suite_loaded',d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'))
    rec('rt79_launcher',d.execute_script("return !!document.querySelector('[data-rt79-open]')"))
    shot(d,'entry')
    click(d,'[data-play-offline]')
    f=WebDriverWait(d,10).until(lambda x:x.find_element(By.CSS_SELECTOR,'#start-form'))
    d.execute_script("arguments[0].elements.playerName.value='Auditoria RT79.1';arguments[0].elements.villageName.value='Aldeia RT79.1';arguments[0].elements.difficulty.value='normal';arguments[0].elements.mapRadius.value='16';arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit();",f)
    WebDriverWait(d,15).until(lambda x:x.execute_script("return !!window.RT76?.state?.()?.activeVillageId"))
    time.sleep(.6);shot(d,'overview')

def seed(d):
    d.execute_script("""
      const s=RT76.state(),v=s.villages[s.activeVillageId];
      v.resources.wood=999999;v.resources.clay=999999;v.resources.iron=999999;
      v.buildQueue=[];v.recruitQueue=[];
      v.units.spear=Math.max(300,Number(v.units.spear||0));
      for(const k of Object.keys(v.buildings||{}))v.buildings[k]=Math.max(Number(v.buildings[k]||0),['farm','warehouse'].includes(k)?20:10);
      s.research=s.research||{queue:[],completed:[]};s.research.queue=[];
      if(v.unitResearch)v.unitResearch.spear=Math.max(1,Number(v.unitResearch.spear||0));
      RT76.save();
    """)

def views(d):
    names=['systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
    for v in names:
        try:click(d,f'[data-view="{v}"]');rec('view_'+v,True);shot(d,'view_'+v)
        except Exception as e:rec('view_'+v,False,repr(e))

def buildings(d):
    click(d,'[data-view="buildings"]')
    keys=d.execute_script("return [...new Set([...document.querySelectorAll('[data-open-building]')].map(x=>x.dataset.openBuilding).filter(Boolean))]")
    rec('building_count_19',len(keys)>=19,str(len(keys)))
    for k in keys[:19]:
        ok=d.execute_script("const k=arguments[0],e=[...document.querySelectorAll('[data-open-building]')].find(x=>x.dataset.openBuilding===k);if(!e)return false;e.click();return true",k)
        rec('building_open_'+k,ok)
        time.sleep(.08)
        rec('building_detail_'+k,d.execute_script("return !!document.querySelector('[data-building-detail=\"'+arguments[0]+'\"]')",k))

def e2e(d):
    seed(d)
    click(d,'[data-view="buildings"]');before=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return v.buildQueue.length")
    key=d.execute_script("const e=document.querySelector('[data-build]:not([disabled])');if(!e)return '';e.click();return e.dataset.build||''")
    time.sleep(.2);after=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return v.buildQueue.length")
    rec('e2e_build',bool(key) and after>before,key)
    click(d,'[data-view="recruit"]');before=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return v.recruitQueue.length")
    key=d.execute_script("const e=document.querySelector('[data-recruit]:not([disabled])');if(!e)return '';const q=document.querySelector('#qty-'+e.dataset.recruit);if(q)q.value='1';e.click();return e.dataset.recruit||''")
    time.sleep(.2);after=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return v.recruitQueue.length")
    rec('e2e_recruit',bool(key) and after>before,key)
    click(d,'[data-view="research"]');before=d.execute_script("return (RT76.state().research?.queue||[]).length")
    key=d.execute_script("const e=document.querySelector('[data-research]:not([disabled])');if(!e)return '';e.click();return e.dataset.research||''")
    time.sleep(.2);after=d.execute_script("return (RT76.state().research?.queue||[]).length")
    rec('e2e_research',bool(key) and after>before,key)
    d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];v.resources.wood=5000;v.resources.clay=1000;v.resources.iron=1000;v.buildings.warehouse=20")
    click(d,'[data-view="market"]');before=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return [v.resources.wood,v.resources.clay]")
    ok=d.execute_script("const f=document.querySelector('#market-form');if(!f)return false;f.elements.from.value='wood';f.elements.to.value='clay';f.elements.amount.value='100';f.requestSubmit();return true")
    time.sleep(.2);after=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return [v.resources.wood,v.resources.clay]")
    rec('e2e_market',ok and after[0]<before[0] and after[1]>before[1],json.dumps({'before':before,'after':after}))
    d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];v.units.spear=Math.max(100,Number(v.units.spear||0))")
    click(d,'[data-view="map"]')
    target=d.execute_script("const s=RT76.state(),t=Object.values(s.villages).find(v=>v.owner!=='player');if(!t)return null;s.ui.mapCenter={x:t.x,y:t.y};return t.id")
    rec('attack_target_exists',bool(target),str(target));click(d,'[data-view="map"]')
    ok=d.execute_script("const id=arguments[0],e=[...document.querySelectorAll('[data-target]')].find(x=>x.dataset.target===id);if(!e)return false;e.click();return true",target);rec('attack_target_rendered',ok)
    before=d.execute_script('return RT76.state().commands.length')
    ok=d.execute_script("const f=document.querySelector('#attack-form');if(!f)return false;const i=f.querySelector('[name=\"attack_spear\"]');if(!i)return false;i.value='1';f.requestSubmit();return true")
    time.sleep(.2);after=d.execute_script('return RT76.state().commands.length');rec('e2e_attack',ok and after>before)
    d.execute_script("const s=RT76.state(),h=s.player.hero;h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(!h.story.inventory.includes('dawnblade'))h.story.inventory.push('dawnblade');h.story.equipment=h.story.equipment||{};delete h.story.equipment.weapon")
    click(d,'[data-view="arsenal"]');ok=d.execute_script("const e=document.querySelector('[data-equip-hero-item=\"dawnblade\"]');if(!e)return false;e.click();return true")
    time.sleep(.2);eq=d.execute_script("return RT76.state().player.hero.story.equipment.weapon||''");rec('e2e_paladin_equipment',ok and eq=='dawnblade',eq)
    name=d.execute_script("RT76.save();return RT76.state().player.name")
    nav(d,URL+'?rt79-reload=1');click(d,'[data-play-offline]');time.sleep(.6)
    loaded=d.execute_script("return RT76.state()?.player?.name||''");rec('e2e_save_reload',loaded==name,loaded)

def mock_online(d):
    mock={'version':79,'settings':{'farm':{'activeTemplate':'A','templates':{'A':{'spear':25},'B':{'axe':40},'C':{'light':40}}},'manager':{},'market':{},'scavenge':{},'villageMeta':{}},'villages':[{'id':'v1','name':'Aldeia RT79','x':500,'y':500,'points':12345,'resources':{'wood':12000,'clay':11000,'iron':10000},'units':{'spear':250,'axe':300,'light':70},'buildings':{'warehouse':18,'watchtower':1},'build_queue':[],'recruit_queue':[]}],'targets':[{'id':'b1','name':'Bárbara 501','x':503,'y':502,'points':1000,'owner_kind':'barbarian','buildings':{'wall':2}}],'incoming_tactical':[{'id':'i1','class':'noble','risk':95,'source_name':'Inimiga','source_x':490,'source_y':490,'target_name':'Aldeia RT79','total_units':101,'arrives_at':'2026-08-18T15:00:00Z'}],'outgoing':[],'scheduled':[],'routes':[],'intel':[],'logs':[],'upcoming_events':[],'scavenge_jobs':[],'resource_transfers':[],'barbarian_ai':[{'village_id':'b1','name':'Bárbara 501','x':503,'y':502,'points':1000,'personality':'balanced','threat_level':2,'wall':2,'next_tick':'2026-08-18T16:00:00Z'}]}
    d.execute_script("""
      window.CLOUD=window.CLOUD||{};CLOUD.session={access_token:'audit'};CLOUD.worldId='w1';CLOUD.url='https://audit.invalid';CLOUD.key='audit';const mock=JSON.parse(arguments[0]);window.__realFetch=window.fetch.bind(window);window.fetch=async(u,o)=>{const s=String(u);if(s.includes('/rest/v1/rpc/rt79_world_maintenance'))return new Response(JSON.stringify({version:79}),{status:200,headers:{'Content-Type':'application/json'}});if(s.includes('/rest/v1/rpc/rt79_dashboard'))return new Response(JSON.stringify(mock),{status:200,headers:{'Content-Type':'application/json'}});if(s.includes('/rest/v1/rpc/'))return new Response(JSON.stringify({ok:true}),{status:200,headers:{'Content-Type':'application/json'}});return __realFetch(u,o)};
    """,json.dumps(mock))

def rt79_and_addons(d):
    mock_online(d);d.execute_script('window.RT79.open()');WebDriverWait(d,10).until(lambda x:x.execute_script("return document.querySelector('#rt79-overlay')?.classList.contains('open')"))
    tabs=['overview','war','farm','market','manager','empire','intel','history']
    for t in tabs:
        click(d,f'[data-rt79-tab="{t}"]');rec('rt79_tab_'+t,True);shot(d,'rt79_'+t)
    d.execute_script("document.querySelector('[data-rt79-close]')?.click();document.querySelector('[data-view=\"overview\"]')?.click()")
    time.sleep(.5)
    rec('village_toolbar',d.execute_script("return !!document.querySelector('.rt79-village-toolbar')"))
    rec('village_19_hitboxes',d.execute_script("return document.querySelectorAll('.village-scene .rt60-village-hitbox').length>=19"))
    rec('authoritative_raster_map',d.execute_script("return !!document.querySelector('.village-scene>.rt54-map-layer')"))
    rec('real_wall_layer',d.execute_script("return !!document.querySelector('.village-scene [data-village-building=\"wall\"]')"))
    artificial=d.execute_script("return document.querySelectorAll('.rt79-road-net,.rt79-wall-perimeter').length");rec('no_artificial_road_wall_overlay',artificial==0,str(artificial))
    d.execute_script('window.RT79.open()');time.sleep(.4);click(d,'[data-rt79-tab="market"]');WebDriverWait(d,8).until(lambda x:x.execute_script("return !!document.querySelector('#rt79-logistics-card')"));rec('logistics_card',True)
    click(d,'[data-rt79-tab="farm"]');WebDriverWait(d,8).until(lambda x:x.execute_script("return !!document.querySelector('#rt79-barb-ai-card')"));rec('barbarian_ai_card',True)
    click(d,'[data-rt79-tab="manager"]');WebDriverWait(d,8).until(lambda x:x.execute_script("return !!document.querySelector('#rt79-group-goals-card')"));rec('group_goals_card',True)

def mobile(d):
    d.set_window_size(390,844);nav(d,URL+'?rt79-mobile-full=1');shot(d,'mobile_entry');rec('mobile_suite',d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'))

def main():
    opts=Options();opts.page_load_strategy='eager';opts.add_argument('--headless=new');opts.add_argument('--disable-gpu');opts.add_argument('--no-sandbox');opts.add_argument('--window-size=1600,1000');opts.add_argument('--disable-dev-shm-usage')
    d=webdriver.Chrome(options=opts)
    proof={}
    try:
        start_game(d);views(d);buildings(d);e2e(d);rt79_and_addons(d);mobile(d)
        failures=[x for x in manifest if x.get('pass') is False]
        proof={'pass':not failures,'browser':'chrome','tests':len([x for x in manifest if 'pass' in x]),'screenshots':len([x for x in manifest if 'file' in x]),'failures':failures,'manifest':manifest}
        if failures:raise AssertionError(json.dumps(failures,ensure_ascii=False))
    except Exception as e:
        proof={'pass':False,'browser':'chrome','error':repr(e),'manifest':manifest}
        try:shot(d,'FAILURE')
        except Exception:pass
        raise
    finally:
        (OUT/'PROVA_BROWSER_RT79.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8');d.quit()
    print(json.dumps({'pass':proof['pass'],'tests':proof['tests'],'screenshots':proof['screenshots']}))

if __name__=='__main__':main()
