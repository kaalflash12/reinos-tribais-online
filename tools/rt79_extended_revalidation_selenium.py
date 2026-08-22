import os,time,json,sys
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import TimeoutException

URL=os.environ.get('RT79_TEST_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT79_BROWSER_REGRESSION';OUT.mkdir(parents=True,exist_ok=True)
VIEWS=['overview','systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
R={'version':'RT79.1','started_at':time.time(),'master':[],'buttons':[],'button_views':{},'page_errors':[],'console_errors':[]}

def js(d,s,*a):return d.execute_script(s,*a)
def ck(name,ok,detail=''):
    row={'name':name,'pass':bool(ok),'detail':detail if isinstance(detail,(str,int,float,bool,type(None))) else json.dumps(detail,ensure_ascii=False)[:3000]}
    R['master'].append(row)
    if not ok: raise AssertionError(f'{name}: {row["detail"]}')
def safe_get(d,url):
    try:d.get(url)
    except TimeoutException:pass

def start_new(d,label='Auditoria Expandida RT79'):
    safe_get(d,URL+'?extended=1&ts='+str(int(time.time()*1000)))
    WebDriverWait(d,25).until(lambda x:js(x,'return !!document.body'))
    WebDriverWait(d,25).until(lambda x:js(x,"return !!document.querySelector('[data-play-offline]')"))
    js(d,"Object.keys(localStorage).filter(k=>k.startsWith('reinos_tribais_ptbr_save_')).forEach(k=>localStorage.removeItem(k));window.confirm=()=>false;window.alert=()=>{}")
    js(d,"document.querySelector('[data-play-offline]').click()")
    f=WebDriverWait(d,8).until(lambda x:x.find_element(By.CSS_SELECTOR,'#start-form'))
    js(d,"arguments[0].elements.playerName.value=arguments[1];arguments[0].elements.villageName.value='Aldeia Auditoria';if(arguments[0].elements.difficulty)arguments[0].elements.difficulty.value='normal';if(arguments[0].elements.mapRadius)arguments[0].elements.mapRadius.value='16';if(arguments[0].elements.startProfile)arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit()",f,label)
    WebDriverWait(d,20).until(lambda x:js(x,'return !!window.RT76?.state?.()?.activeVillageId'))
    WebDriverWait(d,20).until(lambda x:js(x,'return !!window.RT76?.master && window.__RT76_MASTER_PLAN__===true'))
    js(d,"window.__rt79ExtErrors=[];window.addEventListener('error',e=>window.__rt79ExtErrors.push(String(e.error||e.message||'error')));window.addEventListener('unhandledrejection',e=>window.__rt79ExtErrors.push(String(e.reason||'rejection')));window.confirm=()=>false;window.alert=()=>{}")
    return True

def view(d,v):
    js(d,"RT76.test.setView(arguments[0])",v);time.sleep(.12)

def master_contract(d):
    meta=js(d,"return {master:!!RT76.master,flag:window.__RT76_MASTER_PLAN__===true,rt:!!window.RT,api:[typeof RT?.village?.build,typeof RT?.army?.recruit,typeof RT?.army?.attack,typeof RT?.market?.send,typeof RT?.research?.start,typeof RT?.world?.scan]}")
    ck('master.runtime',meta['master'] and meta['flag'] and meta['rt'],meta);ck('master.unified_api',all(x=='function' for x in meta['api']),meta)

    wave=js(d,"""const s=RT76.state(),v=RT76.test.getActiveVillage();v.units.spear=Math.max(v.units.spear||0,200);v.buildings.rally=Math.max(v.buildings.rally||0,20);const t=Object.values(s.villages).find(x=>x.owner==='barbarian'),before=s.rt76.scheduledCommands.length,arr=Date.now()+3600000;const out=RT76.master.planner.planWave({sourceId:v.id,targetId:t.id,troops:{spear:5},arrivalAt:arr,count:3,gapMs:1250,kind:'fake'}),rows=s.rt76.scheduledCommands.slice(before);return {count:out.length,added:rows.length,kinds:rows.map(x=>x.kind),arrivals:rows.map(x=>x.arrivalAt)}""")
    ck('master.planner.wave',wave['count']==3 and wave['added']==3 and wave['kinds']==['fake']*3,wave);ck('master.planner.gap',wave['arrivals'][1]-wave['arrivals'][0]==1250 and wave['arrivals'][2]-wave['arrivals'][1]==1250,wave)

    recall=js(d,"""const s=RT76.state(),v=RT76.test.getActiveVillage(),t=Object.values(s.villages).find(x=>x.owner==='barbarian');v.units.spear=Math.max(v.units.spear||0,100);const before=s.commands.length;RT76.test.sendAttack(t.id,{spear:4},{attackType:'normal'});const c=s.commands.slice(before).find(x=>x.kind==='attack'&&x.phase==='outbound'),z=RT76.master.planner.recall(c.id);return {phase:z.phase,targetId:z.targetId,source:v.id}""")
    ck('master.planner.recall',recall['phase']=='return' and recall['targetId']==recall['source'],recall)

    support=js(d,"""const s=RT76.state(),a=RT76.test.getActiveVillage(),b=Object.values(s.villages).find(x=>x.id!==a.id&&!x._onlineRemote);b.owner='player';b.ownerName=s.player.name;a.units.spear=Math.max(a.units.spear||0,80);const z=RT76.master.planner.scheduleSupport({sourceId:a.id,targetId:b.id,troops:{spear:7},arrivalAt:Date.now()+3600000}),m=s.rt76.master.scheduledSupport.find(y=>y.id===z.id);m.departAt=Date.now()-1;const before=s.commands.length;RT76.master.planner.processSupport(Date.now());const c=s.commands.slice(before).find(y=>y.kind==='support');return {status:m.status,cmd:!!c,q:c?.troops?.spear||0,target:b.id}""")
    ck('master.planner.support',support['status']=='sent' and support['cmd'] and support['q']==7,support)

    farm=js(d,"""const s=RT76.state(),bars=Object.values(s.villages).filter(x=>x.owner==='barbarian').slice(0,2);RT76.master.farm.setRules({maxDistance:100,maxWall:5,maxLossPct:20,reattackMinutes:0,cycleLimit:2});if(bars[0])s.rt76.targetIntel[bars[0].id]={wall:3,lossPct:10,lastVisit:0,visits:1,fullness:.5};if(bars[1])s.rt76.targetIntel[bars[1].id]={wall:12,lossPct:0,lastVisit:0,visits:1,fullness:.5};const c=RT76.master.farm.candidates();return {r:RT76.master.farm.rules(),ids:c.map(x=>x.id),good:bars[0]?.id||'',bad:bars[1]?.id||''}""")
    ck('master.farm.rules',farm['r']['maxWall']==5 and farm['r']['maxLossPct']==20,farm);ck('master.farm.filter',farm['good'] in farm['ids'] and farm['bad'] not in farm['ids'],farm)

    intel=js(d,"""const s=RT76.state(),t=Object.values(s.villages).find(x=>x.owner!=='player');RT76.master.intel.observe(t.id);t.points=(t.points||0)+123;const b=RT76.master.intel.observe(t.id),h=RT76.master.intel.history(t.id),c=RT76.master.intel.classify(t.id);return {len:h.length,delta:b.pointDelta,growing:c.growing,id:t.id}""")
    ck('master.intel.history',intel['len']>=2 and intel['delta']==123 and intel['growing'],intel)
    inc=js(d,"""const s=RT76.state(),dst=RT76.test.getActiveVillage(),a=Object.values(s.villages).find(x=>x.id!==dst.id&&x.owner!=='player');if(!a)return {missingSource:true};dst.buildings.watchtower=20;return RT76.master.intel.incoming({id:'i',kind:'attack',phase:'outbound',sourceId:a.id,targetId:dst.id,troops:{spear:300,ram:12},attackType:'normal',arriveAt:Date.now()+60000})""")
    ck('master.intel.watchtower',not inc.get('missingSource') and inc['origin']!='?' and inc['type']=='Ataque' and inc['exactTroops']['spear']==300,inc)

    market=js(d,"""const s=RT76.state(),a=RT76.test.getActiveVillage(),b=Object.values(s.villages).find(x=>x.id!==a.id&&!x._onlineRemote);b.owner='player';b.ownerName=s.player.name;a.buildings.market=20;b.buildings.market=20;a.resources.wood=100000;b.resources.wood=0;RT76.master.market.addRoute({sourceId:a.id,targetId:b.id,resource:'wood',amount:2500,minSource:5000,intervalMs:60000});const before=s.commands.length,n=RT76.master.market.runRoutes(Date.now()+120000),cmd=s.commands.slice(before).find(x=>x.kind==='trade');RT76.master.market.request({targetId:b.id,resource:'clay',amount:1000});a.resources.clay=100000;const f=RT76.master.market.fulfillRequests(5);return {n,cmd:!!cmd,f,b:b.id}""")
    ck('master.market.route',market['n']>=1 and market['cmd'],market);ck('master.market.request',market['f']>=1,market)

    jobs=js(d,"""const s=RT76.state(),a=RT76.test.getActiveVillage(),b=Object.values(s.villages).find(x=>x.id!==a.id&&x.owner==='player');a.resources.iron=100000;a.buildings.market=20;b.buildings.market=20;const j=RT76.master.jobs.enqueue('TRADE',{sourceId:a.id,targetId:b.id,resources:{iron:333}},Date.now()-1),n=RT76.master.jobs.process(Date.now(),10),row=RT76.master.jobs.list().find(x=>x.id===j.id);return {n,status:row.status}""")
    ck('master.jobs.execute',jobs['n']>=1 and jobs['status']=='done',jobs)

    ai=js(d,"""const s=RT76.state();s.rt76.master.aiJobs=[];const n=RT76.master.ai.planJobs(Date.now()),profiles=Object.keys(RT76.master.ai.profiles);return {n,profiles,planned:s.rt76.master.aiJobs.filter(x=>x.status==='planned').length}""")
    ck('master.ai.profiles',set(ai['profiles'])=={'raider','warden','expander','opportunist'},ai);ck('master.ai.jobs',ai['n']>0 and ai['planned']>0,ai)

    gov=js(d,"""const v=RT76.test.getActiveVillage();RT76.master.governor.setRole(v.id,'defensive');return {role:RT76.master.governor.role(v.id),profiles:Object.keys(RT76.master.governor.profiles)}""")
    ck('master.governor',gov['role']=='defensive' and len(gov['profiles'])==4,gov)

    tribe=js(d,"""const s=RT76.state();s.player.tribe='Contrato';s.player.tribeData={name:'Contrato',level:1,xp:0,treasury:{wood:50000,clay:50000,iron:50000},totalDonated:0,technologies:{economy:0,logistics:0,war:0,command:0,fellowship:0},diplomacy:{pacts:[],allies:[],enemies:[]},rights:{duke:true,baron:true,invite:true,diplomacy:true,circularMail:true,forumMod:true,hiddenForums:true,trustedForums:true},forum:[],claimedObjectives:[],supportRequests:[],wall:[]};const p=RT76.master.tribeProjects.create('roads'),z=RT76.master.tribeProjects.contribute(p.id,{wood:15000,clay:10000,iron:5000});return {status:z.status,rank:RT76.master.tribeProjects.ranking().length}""")
    ck('master.tribe.project',tribe['status']=='complete' and tribe['rank']>=1,tribe)

    for name,sel in [('rally','#rt76-master-planner'),('market','#rt76-master-logistics'),('manager','#rt76-master-governor'),('systems','#rt76-master-engine'),('map','#rt76-master-intel'),('tribe','#rt76-master-tribe')]:
        view(d,name); ck('master.ui.'+name,js(d,"return document.querySelector(arguments[0])!==null",sel),sel)

    view(d,'map');context=js(d,"""const cell=document.querySelector('.map-cell[data-target],.rt22-map-cell[data-target]');if(!cell)return false;cell.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:250,clientY:200}));return !!document.querySelector('#rt76-map-context')""")
    ck('master.map.context',context,context)

    js(d,"const v=RT76.test.getActiveVillage();RT76.master.governor.setRole(v.id,'military');RT76.master.farm.setRules({maxDistance:77});RT76.save()")
    safe_get(d,URL+'?masterreload=1');WebDriverWait(d,25).until(lambda x:js(x,"return !!document.querySelector('[data-play-offline]')"));js(d,"document.querySelector('[data-play-offline]').click()");WebDriverWait(d,20).until(lambda x:js(x,'return !!window.RT76?.master && !!RT76.state()'))
    pers=js(d,"return {d:RT76.master.farm.rules().maxDistance,roles:Object.values(RT76.master.ensure().villageRoles)}")
    ck('master.persistence',pers['d']==77 and 'military' in pers['roles'],pers)


def seed_buttons(d):
    return js(d,"""const s=RT76.state(),v=s.villages[s.activeVillageId],defs=window.D||window.GAME_DATA||{};v.resources=v.resources||{};for(const k of ['wood','clay','iron'])v.resources[k]=999999999;v.resources.lastUpdate=Date.now();v.buildQueue=[];v.recruitQueue=[];v.unitResearchQueue=[];v.unitResearch={};const bd=defs.buildings||{};for(const k of Object.keys(v.buildings||{})){const mx=Number(bd[k]?.max||30);let lvl=Math.min(Math.max(0,mx-1),10);if(k==='farm'||k==='warehouse')lvl=Math.max(1,mx-1);if(mx<=1)lvl=0;v.buildings[k]=lvl;}v.units=v.units||{};for(const k of Object.keys(defs.units||{}))v.units[k]=Math.max(Number(v.units[k]||0),k==='spear'?500:25);s.player.crowns=999999;s.player.premium=999999;s.player.icash=999999;s.player.research=s.player.research||{queue:[],completed:[]};s.player.research.queue=[];s.player.research.completed=[];const h=s.player.hero;if(h){try{ensureHeroStoryState(h)}catch(e){};h.level=Math.max(20,Number(h.level||0));h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(window.HERO_ITEMS)for(const id of Object.keys(HERO_ITEMS))if(!h.story.inventory.includes(id))h.story.inventory.push(id);h.story.equipment=h.story.equipment||{};}const other=Object.values(s.villages).find(x=>x.id!==v.id&&x.owner==='barbarian');if(other){other.owner='player';other.ownerName=s.player.name;other.buildings=other.buildings||{};other.buildings.market=Math.max(10,Number(other.buildings.market||0));other.buildings.rally=Math.max(10,Number(other.buildings.rally||0));}RT76.save();window.__rt79ButtonBaseline=JSON.stringify(s);window.confirm=()=>false;window.alert=()=>{};window.__rt79ExtErrors=[];return {villages:Object.keys(s.villages).length,buildings:Object.keys(v.buildings||{}).length,units:Object.keys(v.units||{}).length}""")

def restore_view(d,v):
    js(d,"""const fresh=JSON.parse(window.__rt79ButtonBaseline),s=RT76.state();for(const k of Object.keys(s))delete s[k];Object.assign(s,fresh);window.__rt79ExtErrors=[];window.confirm=()=>false;window.alert=()=>{};try{document.querySelector('[data-rt79-close]')?.click()}catch(e){};try{RT76.test.setView(arguments[0])}catch(e){currentView=arguments[0];renderAll()}""",v);time.sleep(.045)

def visible_controls(d):
    return js(d,"""const vis=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};return [...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis).map((e,i)=>({i,text:(e.innerText||e.value||e.getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ').slice(0,180),data:{...e.dataset},disabled:!!e.disabled,type:e.type||'',form:e.form?.id||'',cls:String(e.className||'').slice(0,220)}))""")

def prep_control(d,fp,index):
    js(d,"""const fp=arguments[0],idx=arguments[1],s=RT76.state(),v=s.villages[s.activeVillageId],dd=fp.data||{},defs=window.D||window.GAME_DATA||{};for(const k of ['wood','clay','iron'])v.resources[k]=999999999;v.buildQueue=[];v.recruitQueue=[];v.unitResearchQueue=[];if(dd.build&&v.buildings[dd.build]!=null){const mx=Number(defs.buildings?.[dd.build]?.max||30);v.buildings[dd.build]=Math.max(0,Math.min(Number(v.buildings[dd.build]||0),mx-1));}if(dd.recruit){v.unitResearch=v.unitResearch||{};v.unitResearch[dd.recruit]=Math.max(1,Number(v.unitResearch[dd.recruit]||0));}if(dd.unitResearch){v.unitResearch=v.unitResearch||{};v.unitResearch[dd.unitResearch]=0;}if(dd.research&&s.player?.research){s.player.research.queue=[];s.player.research.completed=(s.player.research.completed||[]).filter(x=>x!==dd.research);}if(dd.equipHeroItem&&s.player?.hero){const h=s.player.hero;h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(!h.story.inventory.includes(dd.equipHeroItem))h.story.inventory.push(dd.equipHeroItem);}s.player.crowns=999999;s.player.premium=999999;s.player.icash=999999;const vis=e=>{const z=getComputedStyle(e),r=e.getBoundingClientRect();return z.display!=='none'&&z.visibility!=='hidden'&&Number(z.opacity||1)>0&&r.width>1&&r.height>1};const arr=[...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis),el=arr[idx],form=el?.form;if(form){for(const e of [...form.elements]){if(e.disabled||['hidden','submit','button'].includes(e.type))continue;const n=(e.name||e.id||'').toLowerCase();if(e.tagName==='SELECT'){const o=[...e.options].find(o=>!o.disabled&&o.value!=='')||[...e.options].find(o=>!o.disabled);if(o)e.value=o.value;continue}if(e.type==='checkbox'||e.type==='radio'){if(e.required)e.checked=true;continue}if(e.type==='number'||e.type==='range'){let q=Number(e.value);if(!Number.isFinite(q)||q<=0)q=Math.max(1,Number(e.min||1));if(e.max!==''&&Number.isFinite(Number(e.max)))q=Math.min(q,Number(e.max));e.value=String(q);continue}if(e.type==='datetime-local'){const z=new Date(Date.now()+3600000);e.value=new Date(z.getTime()-z.getTimezoneOffset()*60000).toISOString().slice(0,16);continue}if(e.type==='email'){e.value='audit@example.com';continue}if(e.type==='password'){e.value='Audit123!';continue}if(n==='x'||n.endsWith('_x')){e.value='500';continue}if(n==='y'||n.endsWith('_y')){e.value='500';continue}if(n.includes('amount')||n.includes('quant')||n.includes('qty')){e.value='100';continue}if(!e.value)e.value=e.tagName==='TEXTAREA'?'Teste funcional RT79':'Auditoria RT79';}}RT76.save()""",fp,index)

def button_matrix(d):
    seed=seed_buttons(d);R['button_seed']=seed
    for v in VIEWS:
        restore_view(d,v);fps=visible_controls(d);R['button_views'][v]=len(fps)
        for i,fp in enumerate(fps):
            restore_view(d,v);cur=visible_controls(d)
            if i>=len(cur):
                R['buttons'].append({'view':v,'i':i,'text':fp.get('text',''),'pass':False,'status':'MISSING_AFTER_RESET'});continue
            row=cur[i]
            if row.get('disabled'):
                R['buttons'].append({'view':v,**row,'pass':True,'status':'DISABLED_EXPECTED','effects':['disabled']});continue
            prep_control(d,row,i)
            before=js(d,"window.__beforeButtonState=JSON.stringify(RT76.state());window.__beforeButtonDom=document.querySelector('#app')?.innerHTML||'';return {view:String(window.currentView||''),errors:(window.__rt79ExtErrors||[]).length}")
            err=''
            try:
                js(d,"""const idx=arguments[0],vis=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};const a=[...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis);if(!a[idx])throw Error('button index missing');a[idx].click()""",i);time.sleep(.025)
            except Exception as e:err=repr(e)
            try:
                after=js(d,"const st=JSON.stringify(RT76.state()),dom=document.querySelector('#app')?.innerHTML||'',effects=[];if(st!==window.__beforeButtonState)effects.push('state');if(String(window.currentView||'')!==arguments[0])effects.push('view');if(dom!==window.__beforeButtonDom)effects.push('dom');return {effects,errors:[...(window.__rt79ExtErrors||[])]}",before['view'])
            except Exception as e:after={'effects':[],'errors':[repr(e)]}
            ok=(not err and not after['errors'])
            R['buttons'].append({'view':v,**row,'pass':ok,'status':'CLICKED' if ok else 'FAIL','effects':after['effects'],'error':err or ' | '.join(after['errors'])})
        print(f'RT79 buttons {v}: {len(fps)}; cumulative={len(R["buttons"])}',flush=True)

    restore_view(d,'overview')
    modal={'available':False,'pass':True}
    if js(d,"return !!document.querySelector('[data-cloud-login]')"):
        modal['available']=True;js(d,"document.querySelector('[data-cloud-login]').click()");time.sleep(.08);has=js(d,"return !!document.querySelector('[data-close-modal]')")
        if has:js(d,"document.querySelector('[data-close-modal]').click()");time.sleep(.04)
        modal['pass']=has
    R['special_modal']=modal

    restore_view(d,'settings');reset={'available':False,'pass':True}
    if js(d,"return !!document.querySelector('[data-reset-game]')"):
        reset['available']=True;js(d,"window.confirm=()=>true;document.querySelector('[data-reset-game]').click()");time.sleep(.45);reset['pass']=js(d,"return !!document.querySelector('[data-play-offline]')||!!document.querySelector('#start-form')")
    R['actual_reset']=reset


def main():
    opts=Options();opts.page_load_strategy='eager';opts.add_argument('--headless=new');opts.add_argument('--no-sandbox');opts.add_argument('--disable-gpu');opts.add_argument('--disable-dev-shm-usage');opts.add_argument('--window-size=1600,1000');opts.set_capability('goog:loggingPrefs',{'browser':'ALL'})
    d=webdriver.Chrome(options=opts);d.set_page_load_timeout(35);d.set_script_timeout(20)
    try:
        start_new(d,'Contrato Mestre RT79');master_contract(d)
        start_new(d,'Botões Individuais RT79');button_matrix(d)
        try:
            logs=d.get_log('browser');R['console_errors']=[x for x in logs if x.get('level')=='SEVERE' and 'favicon' not in x.get('message','').lower()]
        except Exception:pass
    except Exception as e:
        R['fatal']=repr(e)
    finally:
        try:d.quit()
        except Exception:pass
    R['duration_s']=time.time()-R['started_at'];R['master_pass']=sum(1 for x in R['master'] if x['pass']);R['master_fail']=sum(1 for x in R['master'] if not x['pass']);R['button_total']=len(R['buttons']);R['button_pass']=sum(1 for x in R['buttons'] if x.get('pass'));R['button_fail']=R['button_total']-R['button_pass'];R['disabled_expected']=sum(1 for x in R['buttons'] if x.get('status')=='DISABLED_EXPECTED');R['ok']=not R.get('fatal') and R['master_fail']==0 and R['button_fail']==0 and R.get('special_modal',{}).get('pass',True) and R.get('actual_reset',{}).get('pass',True) and not R['page_errors'] and not R['console_errors']
    (OUT/'RT79_EXTENDED_REVALIDATION.json').write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf-8')
    summary={k:R.get(k) for k in ['version','duration_s','master_pass','master_fail','button_total','button_pass','button_fail','disabled_expected','ok','fatal','special_modal','actual_reset','button_views','console_errors']};(OUT/'RT79_EXTENDED_REVALIDATION_SUMMARY.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(summary,ensure_ascii=False,indent=2));raise SystemExit(0 if R['ok'] else 1)

if __name__=='__main__':main()
