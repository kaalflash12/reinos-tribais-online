from pathlib import Path
from playwright.sync_api import sync_playwright
import json,time

BASE='http://127.0.0.1:8765/index.html?rt76feature=1'
OUT=Path('RT76_FEATURE_E2E'); OUT.mkdir(exist_ok=True)
R={'checks':{},'failures':[],'page_errors':[],'console_errors':[],'started_at':time.time()}

def check(name,cond,detail=''):
    R['checks'][name]=bool(cond)
    if not cond:R['failures'].append({'check':name,'detail':str(detail)[:1400]})

def start_local(page):
    page.goto(BASE,wait_until='domcontentloaded',timeout=45000)
    page.wait_for_timeout(700)
    off=page.locator('[data-play-offline]').first
    if off.count() and off.is_visible():off.click();page.wait_for_timeout(450)
    form=page.locator('#start-form')
    if form.count() and form.is_visible():
        form.locator('[name=playerName]').fill('RT76 Feature E2E');form.locator('[name=villageName]').fill('Aldeia RT76 Feature');form.locator('button[type=submit],button:not([type])').last.click()
    page.wait_for_selector('.game-shell',timeout=20000)
    page.wait_for_function('window.RT76 && window.__RT76_PLAN_APPLIED__ === true && window.__RT76_WAVE2_APPLIED__ === true')
    page.wait_for_timeout(500)

def view(page,name):page.evaluate('(v)=>RT76.test.setView(v)',name);page.wait_for_timeout(350)
def shot(page,name):page.screenshot(path=str(OUT/name),full_page=True)

def run(page):
    start_local(page)
    meta=page.evaluate('''()=>({title:document.title,api:RT76.version,version:RT76.test.getState().version,marker:!!window.__RT76_PLAN_APPLIED__,wave2:!!window.__RT76_WAVE2_APPLIED__})''')
    check('meta.rt76',meta.get('title')=='Reinos Tribais — RT76 Integrado' and meta.get('api')=='76.1' and meta.get('version')==76 and meta.get('marker') is True and meta.get('wave2') is True,meta)
    stale=page.evaluate('''()=>{const t=document.body.innerText;return ['Central de Sistemas RT69','CENTRAL OPERACIONAL RT75','RT75 GUIADA','RT75 • ALDEIA INTEGRADA • ONLINE','RT75 • aldeia ativa'].filter(x=>t.includes(x))}''')
    check('visible.no_old_version_labels',len(stale)==0,stale)
    api=page.evaluate('''()=>({build:typeof RT76.engine?.village?.build,attack:typeof RT76.engine?.army?.attack,send:typeof RT76.engine?.market?.send,research:typeof RT76.engine?.research?.start,scan:typeof RT76.engine?.world?.scan,ai:typeof RT76.ai?.activity})''')
    check('engine.unified_action_api',all(v=='function' for v in api.values()),api)

    view(page,'manager')
    check('manager.panel',page.locator('#rt76-manager2').count()==1,page.locator('#rt76-manager2').count())
    research_count=page.locator('#rt76-manager2 select[name=research] option').count();check('manager.research_options',research_count>0,research_count)
    page.evaluate('''()=>RT76.setManagerConfig({researchPriority:[Object.keys(window.RESEARCH_DEFS)[0]],autoScavenge:true})''')
    manager=page.evaluate('()=>RT76.snapshot().manager');check('manager.config_persists_in_state',manager.get('autoScavenge') is True and len(manager.get('researchPriority',[]))==1,manager);shot(page,'desktop-manager.png')

    view(page,'rally')
    for sel in ['#rt76-war','#rt76-farm','#rt76-intel']:check('rally.'+sel[1:],page.locator(sel).count()==1,page.locator(sel).count())
    shot(page,'desktop-rally-before-actions.png')
    scheduled=page.evaluate('''()=>{const s=RT76.test.getState(),v=RT76.test.getActiveVillage();v.buildings.rally=Math.max(v.buildings.rally||0,10);v.units.spear=Math.max(v.units.spear||0,100);const target=Object.values(s.villages).find(x=>x.owner==='barbarian');const before=s.commands.length;const x=RT76.scheduleAttack({sourceId:v.id,targetId:target.id,troops:{spear:5},kind:'attack',arrivalAt:Date.now()+3600000});const planned={departAt:x.departAt,arrivalAt:x.arrivalAt,travel:x.travelDuration};x.departAt=Date.now()-5;RT76.processScheduled(Date.now());return {before,after:s.commands.length,status:x.status,planned,targetId:target.id}}''')
    check('war.schedule_creates_real_command',scheduled.get('after')==scheduled.get('before',0)+1 and scheduled.get('status')=='sent',scheduled);check('war.arrival_math',abs((scheduled['planned']['arrivalAt']-scheduled['planned']['departAt'])-scheduled['planned']['travel'])<5,scheduled)
    farm=page.evaluate('''()=>{const s=RT76.test.getState(),v=RT76.test.getActiveVillage();v.units.spear=Math.max(v.units.spear||0,100);const target=Object.values(s.villages).find(x=>x.owner==='barbarian');RT76.test.sendAttack(target.id,{spear:5},{attackType:'raid'});const c=[...s.commands].reverse().find(x=>x.sourceId===v.id&&x.targetId===target.id&&x.phase==='outbound');if(c)c.arriveAt=Date.now()-10;RT76.test.processCommands(Date.now());const intel=RT76.snapshot().targetIntel[target.id]||null;return {intel,recommendation:RT76.farmRecommendation(target.id),commandFound:!!c}}''')
    check('farm.real_attack_processed',farm.get('commandFound') is True,farm);check('farm.target_memory',bool(farm.get('intel')) and farm['intel'].get('visits',0)>=1 and farm.get('recommendation') in ['A','B','C'],farm)

    view(page,'map')
    check('map.intel_panel',page.locator('#rt76-map-intel').count()==1,page.locator('#rt76-map-intel').count())
    mapres=page.evaluate('''()=>{const rows=RT76.engine.world.scan({kind:'barbarian',maxDistance:60});const first=rows[0];const before=RT76.map.state().selected.length;if(first)RT76.map.toggleTarget(first.id);const after=RT76.map.state();return {count:rows.length,before,after:after.selected.length,coords:RT76.map.selectedCoords(),first:first||null}}''')
    check('map.scan_returns_targets',mapres.get('count',0)>0,mapres);check('map.selection_and_coords',mapres.get('after')==mapres.get('before',0)+1 and '|' in mapres.get('coords',''),mapres);shot(page,'desktop-map-intel.png')

    view(page,'market');check('market.panel',page.locator('#rt76-market2').count()==1,page.locator('#rt76-market2').count())
    market=page.evaluate('''()=>{const s=RT76.test.getState(),src=RT76.test.getActiveVillage();let dst=Object.values(s.villages).find(x=>x.id!==src.id&&!x._onlineRemote);dst.owner='player';dst.ownerName=s.player.name;dst.name='Aldeia Logística E2E';src.buildings.market=20;dst.buildings.market=20;src.resources.wood=100000;src.resources.clay=50000;src.resources.iron=50000;dst.resources.wood=0;RT76.setMarketConfig({minStock:{wood:10000,clay:0,iron:0},cycleLimit:2,autoEqualize:false});const before=dst.resources.wood,n=RT76.equalizeResources();const cmd=[...s.commands].reverse().find(c=>c.targetId===dst.id&&(c.kind==='trade'||c.trade||c.resources));const immediate=dst.resources.wood;if(cmd){cmd.arriveAt=Date.now()-10;RT76.test.processCommands(Date.now())}return {n,before,immediate,after:dst.resources.wood,commandFound:!!cmd,cmdKind:cmd?.kind||null,dst:dst.id}}''')
    check('market.equalize_created_transfer',market.get('n',0)>=1 and market.get('commandFound') is True,market);check('market.no_resource_teleport',market.get('immediate')==market.get('before') and market.get('after',0)>market.get('before',0),market);shot(page,'desktop-market.png')

    view(page,'systems');check('empire.panel',page.locator('#rt76-empire').count()==1,page.locator('#rt76-empire').count());check('ai.activity_panel',page.locator('#rt76-ai-activity').count()==1,page.locator('#rt76-ai-activity').count())
    systems_text=page.locator('.content-panel').inner_text();check('systems.title_rt76','Central de Sistemas RT76' in systems_text,systems_text[:500]);check('systems.api_label','API única ativa' in systems_text,systems_text[-500:]);shot(page,'desktop-systems.png')

    page.evaluate('''()=>{RT76.setMarketConfig({minStock:{wood:7777,clay:2222,iron:3333},cycleLimit:4,autoEqualize:false});RT76.save()}''');page.reload(wait_until='domcontentloaded');page.wait_for_timeout(500)
    off=page.locator('[data-play-offline]').first
    if off.count() and off.is_visible():off.click();page.wait_for_timeout(500)
    page.wait_for_function('window.RT76 && RT76.test && RT76.test.getState() && window.__RT76_WAVE2_APPLIED__')
    persisted=page.evaluate('()=>({wood:RT76.snapshot().market.minStock.wood,selected:RT76.map.state().selected.length})');check('save.rt76_reload',persisted.get('wood')==7777 and persisted.get('selected',0)>=1,persisted)

    page.set_viewport_size({'width':390,'height':844})
    for name,sel in [('rally','#rt76-war'),('map','#rt76-map-intel'),('market','#rt76-market2'),('manager','#rt76-manager2'),('systems','#rt76-empire')]:
        view(page,name);check('mobile.'+name+'.panel',page.locator(sel).count()==1,page.locator(sel).count());overflow=page.evaluate('()=>document.documentElement.scrollWidth-innerWidth');check('mobile.'+name+'.no_body_overflow',overflow<=2,overflow);shot(page,'mobile-'+name+'.png')

with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True);page=browser.new_page(viewport={'width':1600,'height':1000});page.on('pageerror',lambda e:R['page_errors'].append(str(e)));page.on('console',lambda m:R['console_errors'].append(m.text) if m.type=='error' else None)
    try:run(page)
    except Exception as e:R['failures'].append({'check':'uncaught','detail':repr(e)})
    browser.close()
R['finished_at']=time.time();R['duration_s']=R['finished_at']-R['started_at'];R['ok']=not R['failures'] and not R['page_errors'] and not R['console_errors'];(OUT/'result.json').write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(R,ensure_ascii=False,indent=2));raise SystemExit(0 if R['ok'] else 1)
