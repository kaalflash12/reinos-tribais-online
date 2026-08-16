from pathlib import Path
from playwright.sync_api import sync_playwright
import json, sys, time

BASE='http://127.0.0.1:8765/index.html?rt76full=1'
OUT=Path('RT76_EVIDENCIAS_ATUAIS'); OUT.mkdir(exist_ok=True)
VIEWS=['overview','systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
BUILDINGS=['main','timber','clay','iron','farm','warehouse','market','hide','barracks','stable','garage','smith','academy','statue','rally','wall','watchtower','first_church','church']
RESULT={'build':'RT76_CURRENT_AUDIT','checks':{},'failures':[],'warnings':[],'desktop':{},'mobile':{},'functional':{},'started_at':time.time()}

def check(name, cond, detail=''):
    RESULT['checks'][name]=bool(cond)
    if not cond: RESULT['failures'].append({'check':name,'detail':str(detail)[:1000]})
    return bool(cond)

def diag(page):
    return page.evaluate('''() => {
      const vis=e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};
      const broken=[...document.images].filter(i=>vis(i)&&(!i.complete||i.naturalWidth===0)).map(i=>({src:i.getAttribute('src'),alt:i.alt,cls:i.className}));
      const bad=[...document.querySelectorAll('body *')].filter(e=>vis(e)&&/(undefined|NaN|\[object Object\]|�)/.test(e.textContent||'')).slice(0,20).map(e=>({tag:e.tagName,cls:e.className,text:(e.textContent||'').trim().slice(0,180)}));
      return {title:document.title,bodyW:document.documentElement.scrollWidth,viewW:innerWidth,bodyOverflow:document.documentElement.scrollWidth-innerWidth,broken,bad,
        pageErrors:window.__rt76PageErrors||[],consoleErrors:window.__rt76ConsoleErrors||[],
        h1:[...document.querySelectorAll('h1')].filter(vis).map(x=>x.textContent.trim()).slice(0,5)};
    }''')

def bind_errors(page):
    page.add_init_script('window.__rt76PageErrors=[];window.__rt76ConsoleErrors=[];')
    page.on('pageerror',lambda e: page.evaluate('(x)=>window.__rt76PageErrors.push(x)',str(e)) if not page.is_closed() else None)
    page.on('console',lambda m: page.evaluate('(x)=>window.__rt76ConsoleErrors.push(x)',m.text) if (m.type=='error' and not page.is_closed()) else None)

def start_local(page):
    page.goto(BASE,wait_until='domcontentloaded',timeout=45000)
    page.wait_for_timeout(800)
    off=page.locator('[data-play-offline]').first
    if off.count() and off.is_visible():
        off.click(); page.wait_for_timeout(500)
    form=page.locator('#start-form')
    if form.count() and form.is_visible():
        form.locator('[name=playerName]').fill('Auditoria Integral RT76')
        form.locator('[name=villageName]').fill('Aldeia Auditoria RT76')
        form.locator('button[type=submit],button:not([type])').last.click()
    page.wait_for_selector('.game-shell',timeout=20000)
    page.wait_for_timeout(700)

def direct_view(page,view):
    return page.evaluate('''(view)=>{try{modalHtml=''}catch(e){}; currentView=view; renderAll(); return {view:currentView};}''',view)

def capture_view(page,prefix,view):
    clicked=False
    loc=page.locator(f'[data-view="{view}"]').first
    try:
        if loc.count() and loc.is_visible():
            loc.click(timeout=3000); clicked=True
        else: direct_view(page,view)
    except Exception:
        direct_view(page,view)
    page.wait_for_timeout(180)
    d=diag(page)
    page.screenshot(path=str(OUT/f'{prefix}-view-{view}.png'),full_page=True)
    return {'clicked':clicked,'diag':d}

def set_all_buildings_for_tier(page,tier):
    return page.evaluate('''(payload)=>{
      const v=getActiveVillage(), keys=payload.keys, tier=payload.tier, chosen={};
      for(const k of keys){
        const max=D.buildings[k].max||30; let found=0;
        for(let lvl=1;lvl<=max;lvl++){v.buildings[k]=lvl; if(getBuildingVisual(v,k).tier===tier){found=lvl;break;}}
        if(!found){for(let lvl=max;lvl>=1;lvl--){v.buildings[k]=lvl;if(getBuildingVisual(v,k).tier===tier){found=lvl;break;}}}
        v.buildings[k]=found||1; chosen[k]=v.buildings[k];
      }
      currentView='overview'; renderAll(); return chosen;
    }''',{'keys':BUILDINGS,'tier':tier})

def audit_village(page,prefix):
    out={'tiers':{},'buildings':{}}
    # legacy duplicate renderer must not be active/clickable
    legacy=page.evaluate('''() => ({overlay:[...document.querySelectorAll('#rt73-village-overlay')].map(e=>getComputedStyle(e).display),buildings:[...document.querySelectorAll('.rt73-building')].filter(e=>getComputedStyle(e).display!=='none').length,hits:[...document.querySelectorAll('.rt73-hit')].filter(e=>getComputedStyle(e).pointerEvents!=='none'&&getComputedStyle(e).display!=='none').length})''')
    out['legacy']=legacy
    check(f'{prefix}.legacy_rt73_not_active',legacy['buildings']==0 and legacy['hits']==0,legacy)

    # all four visual tiers, all 19 arts loaded from distinct L1..L4 files
    for tier in (1,2,3,4):
        chosen=set_all_buildings_for_tier(page,tier); page.wait_for_timeout(300)
        rows=page.evaluate('''() => [...document.querySelectorAll('.rt75-building-art')].map(e=>({key:e.dataset.villageBuilding,tier:Number(e.dataset.villageTier),src:e.getAttribute('src'),natural:[e.naturalWidth,e.naturalHeight],complete:e.complete,display:getComputedStyle(e).display,rect:[e.getBoundingClientRect().x,e.getBoundingClientRect().y,e.getBoundingClientRect().width,e.getBoundingClientRect().height]}))''')
        out['tiers'][str(tier)]={'levels':chosen,'arts':rows}
        check(f'{prefix}.tier{tier}.19_arts',len(rows)==19,len(rows))
        check(f'{prefix}.tier{tier}.all_match',all(r['tier']==tier for r in rows),rows)
        check(f'{prefix}.tier{tier}.assets_480x400',all(r['complete'] and r['natural']==[480,400] and r['display']!='none' for r in rows),rows)
        check(f'{prefix}.tier{tier}.unique_keys',len({r['key'] for r in rows})==19,rows)
        check(f'{prefix}.tier{tier}.correct_asset_suffix',all(f'_l{tier}.png' in r['src'] for r in rows),[r['src'] for r in rows])
        page.locator('.village-scene').first.screenshot(path=str(OUT/f'{prefix}-village-tier{tier}.png'))

    # hitbox -> correct building detail for every building
    page.evaluate('''()=>{const v=getActiveVillage(); for(const k of Object.keys(D.buildings)) if(!v.buildings[k])v.buildings[k]=1; currentView='overview';renderAll()}'''); page.wait_for_timeout(250)
    check(f'{prefix}.19_hitboxes',page.locator('.village-scene .rt60-village-hitbox').count()==19,page.locator('.village-scene .rt60-village-hitbox').count())
    for key in BUILDINGS:
        direct_view(page,'overview'); page.wait_for_timeout(70)
        hb=page.locator(f'.village-scene .rt60-village-hitbox[data-open-building="{key}"]').first
        rec={'exists':hb.count()>0,'visible':False,'opened':False,'heading':''}
        if hb.count():
            try:
                rec['visible']=hb.is_visible(); hb.click(timeout=2500); page.wait_for_timeout(80)
                rec['opened']=page.evaluate('(k)=>currentView==="building"&&state.ui.selectedBuilding===k',key)
                rec['heading']=' | '.join(page.locator('h1,h2').all_inner_texts()[:5])
                guide=page.locator('.rt65-action-deck,.rt19-building-function-guide,[data-building-function]').count()
                rec['function_ui']=guide
                page.screenshot(path=str(OUT/f'{prefix}-building-{key}.png'),full_page=True)
            except Exception as e: rec['error']=str(e)
        out['buildings'][key]=rec
        check(f'{prefix}.building.{key}.click_open',rec['exists'] and rec['visible'] and rec['opened'],rec)
    return out

def functional_suite(page):
    f={}
    # runtime essentials must be executable in current build
    funcs=page.evaluate('''()=>{const n=['saveState','loadState','updateResources','queueBuilding','processQueues','queueRecruit','queueResearch','processResearchQueue','queueUnitResearch','processUnitResearch','sendAttack','processCommands','createMarketOffer','equipHeroItem','renderAll'];const o={};for(const x of n)o[x]=eval('typeof '+x);return o}''')
    f['functions']=funcs; check('functional.runtime_functions',all(v=='function' for v in funcs.values()),funcs)

    # production with one hour elapsed
    prod=page.evaluate('''()=>{const v=getActiveVillage(); for(const r of RESOURCE_KEYS)v.resources[r]=1000; v.resources.lastUpdate=now()-3600000; const before={wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron}; updateResources(v,now()); return {before,after:{wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron},rates:{wood:productionPerHour(v,'wood'),clay:productionPerHour(v,'clay'),iron:productionPerHour(v,'iron')}}}''')
    f['production']=prod; check('functional.production_increases',all(prod['after'][r]>prod['before'][r] for r in ['wood','clay','iron']),prod)

    # building queue + completion
    build=page.evaluate('''()=>{const v=getActiveVillage();for(const r of RESOURCE_KEYS)v.resources[r]=1e9;for(const k of Object.keys(D.buildings))v.buildings[k]=Math.min(20,D.buildings[k].max||20);v.buildings.main=1;v.buildQueue=[];const before=v.buildings.main;queueBuilding('main');const queued=v.buildQueue.length;const spent=v.resources.wood<1e9;if(v.buildQueue[0])v.buildQueue[0].finishAt=now()-1;processQueues(now());return {before,queued,spent,after:v.buildings.main,remaining:v.buildQueue.length}}''')
    f['building']=build; check('functional.build_queue_and_complete',build['queued']==1 and build['spent'] and build['after']>build['before'] and build['remaining']==0,build)

    # recruit queue + completion
    recruit=page.evaluate('''()=>{const v=getActiveVillage();for(const r of RESOURCE_KEYS)v.resources[r]=1e9;v.buildings.barracks=Math.max(20,v.buildings.barracks||0);v.buildings.farm=Math.max(30,v.buildings.farm||0);v.unitResearch=v.unitResearch||{};v.unitResearch.spear=Math.max(1,v.unitResearch.spear||0);v.recruitQueue=[];const before=v.units.spear||0;queueRecruit('spear',2);const queued=v.recruitQueue.length;if(v.recruitQueue[0])v.recruitQueue[0].finishAt=now()-1;processQueues(now());return {before,queued,after:v.units.spear||0,remaining:v.recruitQueue.length}}''')
    f['recruit']=recruit; check('functional.recruit_queue_and_complete',recruit['queued']>=1 and recruit['after']>=recruit['before']+2 and recruit['remaining']==0,recruit)

    # global research + completion
    research=page.evaluate('''()=>{const v=getActiveVillage();for(const r of RESOURCE_KEYS)v.resources[r]=1e9;for(const k of Object.keys(D.buildings))v.buildings[k]=D.buildings[k].max||30;state.player.research.completed=[];state.player.research.queue=[];let picked=null;for(const id of Object.keys(RESEARCH_DEFS)){queueResearch(id);if(state.player.research.queue.length){picked=id;break;}}const queued=state.player.research.queue.length;if(queued)state.player.research.queue[0].finishAt=now()-1;processResearchQueue(now());return {picked,queued,completed:[...state.player.research.completed]}}''')
    f['research']=research; check('functional.research_queue_and_complete',bool(research['picked']) and research['queued']==1 and research['picked'] in research['completed'],research)

    # unit research + completion
    unitres=page.evaluate('''()=>{const v=getActiveVillage();for(const r of RESOURCE_KEYS)v.resources[r]=1e9;for(const k of Object.keys(D.buildings))v.buildings[k]=D.buildings[k].max||30;v.unitResearch={};v.unitResearchQueue=[];let picked=null;for(const k of RESEARCHABLE_UNITS){queueUnitResearch(k);if(v.unitResearchQueue.length){picked=k;break;}}const queued=v.unitResearchQueue.length;if(queued)v.unitResearchQueue[0].finishAt=now()-1;processUnitResearch(now());return {picked,queued,level:picked?(v.unitResearch[picked]||0):0}}''')
    f['unit_research']=unitres; check('functional.unit_research_queue_and_complete',bool(unitres['picked']) and unitres['queued']==1 and unitres['level']>=1,unitres)

    # local market offer publishes and consumes resource
    market=page.evaluate('''()=>{const v=getActiveVillage();for(const r of RESOURCE_KEYS)v.resources[r]=1e9;state.marketOffers=[];const fd=new FormData();fd.set('give','wood');fd.set('get','clay');fd.set('giveAmount','500');fd.set('getAmount','400');const before=v.resources.wood;createMarketOffer(fd);const own=ensureMarketOffers().filter(o=>o.player);return {before,after:v.resources.wood,own:own.map(o=>({give:o.give,get:o.get,giveAmount:o.giveAmount,getAmount:o.getAmount}))}}''')
    f['market']=market; check('functional.market_create_offer',market['after']==market['before']-500 and len(market['own'])>=1,market)

    # local attack against barbarian, resolve outbound and return without exceptions
    attack=page.evaluate('''()=>{const v=getActiveVillage();v.units.spear=100;v.buildings.rally=Math.max(20,v.buildings.rally||0);const target=Object.values(state.villages).find(x=>x.id!==v.id&&x.owner==='barbarian');if(!target)return {error:'no barbarian'};const reportsBefore=state.reports.length,unitsBefore=v.units.spear;sendAttack(target.id,{spear:5},{attackType:'raid'});const sent=state.commands.filter(c=>c.sourceId===v.id).length;for(const c of state.commands){if(c.phase==='outbound')c.arriveAt=now()-2;if(c.phase==='return')c.returnAt=now()-2;}processCommands(now());for(const c of state.commands){if(c.phase==='return')c.returnAt=now()-2;}processCommands(now());return {target:target.id,sent,reportsBefore,reportsAfter:state.reports.length,unitsBefore,unitsAfter:v.units.spear,commands:state.commands.length}}''')
    f['attack']=attack; check('functional.attack_resolves_report',not attack.get('error') and attack['sent']>=1 and attack['reportsAfter']>attack['reportsBefore'],attack)

    # Paladin item ownership -> equip -> visual loadout contains slot art
    hero=page.evaluate('''()=>{const h=state.player.hero;ensureHeroStoryState(h);const id=Object.keys(HERO_ITEMS)[0],item=HERO_ITEMS[id];if(!h.story.inventory.includes(id))h.story.inventory.push(id);equipHeroItem(id);currentView='hero';renderAll();return {id,slot:item.slot,equipped:h.story.equipment[item.slot],owned:hasHeroItem(id),itemArt:getHeroItemArt(id)}}''')
    page.wait_for_timeout(150)
    hero['renderedImages']=page.locator('.rt19-paladin-hero img,.hero-banner img,.hero-loadout img').count()
    f['hero']=hero; check('functional.hero_item_equip',hero['owned'] and hero['equipped']==hero['id'] and hero['renderedImages']>0,hero)

    # save/reload persistence with a sentinel value
    page.evaluate('''()=>{const v=getActiveVillage();v.resources.wood=424242;saveState(true)}'''); page.wait_for_timeout(120)
    page.reload(wait_until='domcontentloaded'); page.wait_for_timeout(550)
    off=page.locator('[data-play-offline]').first
    if off.count() and off.is_visible(): off.click();page.wait_for_timeout(400)
    saved=page.evaluate('''()=>({hasGame:!!document.querySelector('.game-shell'),wood:getActiveVillage()?.resources?.wood,worldId:CLOUD.worldId,saveKeys:Object.keys(localStorage).filter(k=>k.includes('reinos_tribais'))})''')
    f['save_reload']=saved; check('functional.local_save_reload',saved['hasGame'] and saved['wood']==424242 and saved['worldId'] is None and len(saved['saveKeys'])>0,saved)
    return f

def run_case(pw,prefix,viewport,do_functional=False):
    browser=pw.chromium.launch(headless=True)
    page=browser.new_page(viewport=viewport)
    bind_errors(page); start_local(page)
    base=diag(page)
    check(f'{prefix}.title_rt75','RT75' in base['title'],base['title'])
    check(f'{prefix}.no_initial_broken_images',len(base['broken'])==0,base['broken'])
    check(f'{prefix}.no_body_horizontal_overflow',base['bodyOverflow']<=3,base)
    viewres={}
    for view in VIEWS:
        r=capture_view(page,prefix,view); viewres[view]=r
        d=r['diag']
        check(f'{prefix}.view.{view}.no_broken_images',len(d['broken'])==0,d['broken'])
        check(f'{prefix}.view.{view}.no_bad_runtime_text',len(d['bad'])==0,d['bad'])
        check(f'{prefix}.view.{view}.no_body_overflow',d['bodyOverflow']<=3,d)
    village=audit_village(page,prefix)
    fun=functional_suite(page) if do_functional else None
    final=diag(page)
    check(f'{prefix}.zero_page_errors',len(final['pageErrors'])==0,final['pageErrors'])
    # console network/image errors count as real failures; ignore expected favicon 404 only
    errs=[x for x in final['consoleErrors'] if 'favicon' not in x.lower()]
    check(f'{prefix}.zero_console_errors',len(errs)==0,errs)
    RESULT[prefix]={'base':base,'views':viewres,'village':village,'functional':fun,'final':final}
    browser.close()

with sync_playwright() as pw:
    run_case(pw,'desktop',{'width':1920,'height':1080},True)
    run_case(pw,'mobile',{'width':390,'height':844},False)

RESULT['finished_at']=time.time(); RESULT['duration_s']=RESULT['finished_at']-RESULT['started_at']
(OUT/'RT76_FULL_REGRESSION.json').write_text(json.dumps(RESULT,indent=2,ensure_ascii=False),encoding='utf-8')
summary={'checks':len(RESULT['checks']),'pass':sum(1 for v in RESULT['checks'].values() if v),'fail':len(RESULT['failures']),'failures':RESULT['failures'],'duration_s':RESULT['duration_s']}
(OUT/'RESUMO.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(summary,indent=2,ensure_ascii=False))
if RESULT['failures']: sys.exit(1)
