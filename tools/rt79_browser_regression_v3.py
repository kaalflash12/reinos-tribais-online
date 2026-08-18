import os,time,json
from selenium.common.exceptions import TimeoutException
import rt79_browser_regression as r

PUBLIC=os.environ.get('RT79_TEST_URL','http://127.0.0.1:8765/')
orig_base_views=r.base_views

def safe_nav(d,url,timeout=25):
    d.set_page_load_timeout(timeout)
    try:d.get(url)
    except TimeoutException:
        try:d.execute_script('window.stop()')
        except Exception:pass
    r.WebDriverWait(d,25).until(lambda x:x.execute_script("return document.readyState==='interactive'||document.readyState==='complete'"))
    time.sleep(.6)

def start_local(d):
    safe_nav(d,PUBLIC+'?rt79-e2e=3')
    d.execute_script("Object.keys(localStorage).filter(k=>k.startsWith('reinos_tribais_ptbr_save_')).forEach(k=>localStorage.removeItem(k));")
    r.require(d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'),'RT79 suite not loaded')
    r.require(d.execute_script("return !!document.querySelector('[data-rt79-open]')"),'RT79 launcher absent')
    r.shot(d,'00_entry_rt79_loaded')
    r.click(d,'[data-play-offline]')
    f=d.find_element(r.By.CSS_SELECTOR,'#start-form')
    d.execute_script("arguments[0].elements.playerName.value='Auditoria RT79';arguments[0].elements.villageName.value='Aldeia RT79';arguments[0].elements.difficulty.value='normal';arguments[0].elements.mapRadius.value='16';arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit();",f)
    time.sleep(1.2)
    r.require(d.execute_script('return !!window.RT76?.state?.()'),'RT76/RT79 state bridge absent')
    r.shot(d,'01_overview_desktop')

def prep_state(d):
    d.execute_script("""
      const s=window.RT76.state(),v=s.villages[s.activeVillageId];
      v.resources.wood=50000;v.resources.clay=50000;v.resources.iron=50000;
      v.buildQueue=[];v.recruitQueue=[];v.units.spear=Math.max(150,Number(v.units.spear||0));
      for(const k of ['main','barracks','stable','garage','smith','market','timber','clay','iron','farm','warehouse','wall','academy','watchtower','statue','rally','hide']) if(v.buildings[k]!==undefined)v.buildings[k]=Math.max(Number(v.buildings[k]||0),k==='farm'||k==='warehouse'?20:10);
      s.research=s.research||{queue:[],completed:[]};s.research.queue=[];
      if(v.unitResearch){v.unitResearch.spear=Math.max(1,Number(v.unitResearch.spear||0));}
      window.RT76.save();
    """)

def building_details(d):
    r.click(d,'[data-view="buildings"]')
    keys=d.execute_script("return [...new Set([...document.querySelectorAll('[data-open-building]')].map(x=>x.dataset.openBuilding).filter(Boolean))]")
    r.require(len(keys)>=19,f'expected 19 building keys, got {len(keys)}')
    for k in keys[:19]:
        ok=d.execute_script("const k=arguments[0],e=[...document.querySelectorAll('[data-open-building]')].find(x=>x.dataset.openBuilding===k);if(e){e.click();return true}return false",k)
        r.require(ok,'building opener missing '+k);time.sleep(.12)
        r.require(d.execute_script("return !!document.querySelector('[data-building-detail=\"'+arguments[0]+'\"]')",k),'building detail missing '+k)
        r.shot(d,'building_'+k);r.record('building_'+k,True)
    r.record('building_count_19',len(keys)>=19,str(len(keys)))

def e2e(d):
    prep_state(d)
    r.click(d,'[data-view="buildings"]')
    before=d.execute_script("const s=RT76.state();return s.villages[s.activeVillageId].buildQueue.length")
    ok=d.execute_script("const e=document.querySelector('[data-build]:not([disabled])');if(e){e.click();return e.dataset.build}return ''")
    time.sleep(.3);after=d.execute_script("const s=RT76.state();return s.villages[s.activeVillageId].buildQueue.length")
    r.require(ok and after>before,'build E2E did not queue');r.record('e2e_build',True,ok);r.shot(d,'e2e_build')
    r.click(d,'[data-view="recruit"]');before=d.execute_script("const s=RT76.state();return s.villages[s.activeVillageId].recruitQueue.length")
    ok=d.execute_script("const e=document.querySelector('[data-recruit]:not([disabled])');if(!e)return '';const q=document.querySelector('#qty-'+e.dataset.recruit);if(q)q.value='1';e.click();return e.dataset.recruit")
    time.sleep(.3);after=d.execute_script("const s=RT76.state();return s.villages[s.activeVillageId].recruitQueue.length")
    r.require(ok and after>before,'recruit E2E did not queue');r.record('e2e_recruit',True,ok);r.shot(d,'e2e_recruit')
    r.click(d,'[data-view="research"]');before=d.execute_script("return (RT76.state().research?.queue||[]).length")
    ok=d.execute_script("const e=document.querySelector('[data-research]:not([disabled])');if(e){e.click();return e.dataset.research}return ''")
    time.sleep(.3);after=d.execute_script("return (RT76.state().research?.queue||[]).length")
    r.require(ok and after>before,'research E2E did not queue');r.record('e2e_research',True,ok);r.shot(d,'e2e_research')
    d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];v.resources.wood=5000;v.resources.clay=1000;v.resources.iron=1000;v.buildings.warehouse=20;")
    r.click(d,'[data-view="market"]');before=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return [v.resources.wood,v.resources.clay]")
    ok=d.execute_script("const f=document.querySelector('#market-form');if(!f)return false;f.elements.from.value='wood';f.elements.to.value='clay';f.elements.amount.value='100';f.requestSubmit();return true")
    time.sleep(.25);after=d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];return [v.resources.wood,v.resources.clay]")
    r.require(ok and after[0]<before[0] and after[1]>before[1],'market E2E did not exchange resources');r.record('e2e_market',True,json.dumps({'before':before,'after':after}));r.shot(d,'e2e_market')
    d.execute_script("const s=RT76.state(),v=s.villages[s.activeVillageId];v.units.spear=Math.max(50,Number(v.units.spear||0));")
    r.click(d,'[data-view="map"]')
    target=d.execute_script("const s=RT76.state(),src=s.villages[s.activeVillageId],t=Object.values(s.villages).find(v=>v.owner!=='player');if(!t)return null;s.ui.mapCenter={x:t.x,y:t.y};return t.id")
    r.require(target,'no attack target')
    r.click(d,'[data-view="map"]')
    ok=d.execute_script("const id=arguments[0],e=[...document.querySelectorAll('[data-target]')].find(x=>x.dataset.target===id);if(e){e.click();return true}return false",target)
    r.require(ok,'target not rendered on map');time.sleep(.25)
    before=d.execute_script("return RT76.state().commands.length")
    ok=d.execute_script("const f=document.querySelector('#attack-form');if(!f)return false;const i=f.querySelector('[name=\"attack_spear\"]');if(!i)return false;i.value='1';f.requestSubmit();return true")
    time.sleep(.3);after=d.execute_script("return RT76.state().commands.length")
    r.require(ok and after>before,'attack E2E did not create command');r.record('e2e_attack',True,target);r.shot(d,'e2e_attack')
    d.execute_script("const s=RT76.state(),h=s.player.hero;h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(!h.story.inventory.includes('dawnblade'))h.story.inventory.push('dawnblade');h.story.equipment=h.story.equipment||{};delete h.story.equipment.weapon;")
    r.click(d,'[data-view="arsenal"]')
    ok=d.execute_script("const e=document.querySelector('[data-equip-hero-item=\"dawnblade\"]');if(e){e.click();return true}return false")
    time.sleep(.25);equipped=d.execute_script("return RT76.state().player.hero.story.equipment.weapon")
    r.require(ok and equipped=='dawnblade','Paladin equipment E2E failed');r.record('e2e_paladin_equipment',True,equipped);r.shot(d,'e2e_paladin_equipment')
    name=d.execute_script("RT76.save();return RT76.state().player.name")
    safe_nav(d,PUBLIC+'?rt79-reload=3')
    r.click(d,'[data-play-offline]');time.sleep(.8)
    loaded=d.execute_script("return window.RT76?.state?.()?.player?.name||''")
    r.require(loaded==name,'save/reload E2E failed');r.record('e2e_save_reload',True,loaded);r.shot(d,'e2e_save_reload')

def base_views(d):
    orig_base_views(d);building_details(d);e2e(d)

def mobile(d):
    d.set_window_size(390,844);safe_nav(d,PUBLIC+'?rt79-mobile=3')
    r.require(d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'),'RT79 missing mobile');r.shot(d,'mobile_entry')
    if d.execute_script("return !!document.querySelector('[data-play-offline]')"):r.click(d,'[data-play-offline]');time.sleep(.5)
    r.shot(d,'mobile_game_or_start')
    if d.execute_script("return !!document.querySelector('[data-rt79-open]')"):
        r.install_mock(d);r.click(d,'[data-rt79-open]');time.sleep(.5);r.shot(d,'mobile_rt79')

r.start_local=start_local;r.base_views=base_views;r.mobile=mobile;r.main()
