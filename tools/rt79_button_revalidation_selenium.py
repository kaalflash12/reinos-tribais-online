import os,time,json,sys
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import TimeoutException

URL=os.environ.get('RT79_TEST_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT79_BROWSER_REGRESSION';OUT.mkdir(parents=True,exist_ok=True)
VIEWS=['overview','systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
R={'version':'RT79.1','method':'literal visible button instances clicked individually from the same restored current-state baseline','views':{},'results':[],'fatal':None,'page_errors':[],'started_at':time.time()}

def js(d,s,*a): return d.execute_script(s,*a)
def safe_get(d,u):
    try:d.get(u)
    except TimeoutException:pass

def start(d):
    safe_get(d,URL+'?buttonmatrix=1&ts='+str(int(time.time()*1000)))
    WebDriverWait(d,25).until(lambda x:js(x,"return !!document.querySelector('[data-play-offline]')"))
    js(d,"Object.keys(localStorage).filter(k=>k.startsWith('reinos_tribais_ptbr_save_')).forEach(k=>localStorage.removeItem(k));window.confirm=()=>false;window.alert=()=>{};document.querySelector('[data-play-offline]').click()")
    WebDriverWait(d,8).until(lambda x:js(x,"return !!document.querySelector('#start-form')"))
    js(d,"const f=document.querySelector('#start-form');f.elements.playerName.value='Auditoria Botões RT79';f.elements.villageName.value='Aldeia Botões';if(f.elements.difficulty)f.elements.difficulty.value='normal';if(f.elements.mapRadius)f.elements.mapRadius.value='16';if(f.elements.startProfile)f.elements.startProfile.value='military';f.requestSubmit()")
    WebDriverWait(d,20).until(lambda x:js(x,'return !!window.RT76?.state?.()?.activeVillageId'))
    WebDriverWait(d,20).until(lambda x:js(x,'return !!window.__RT79_STRATEGY_SUITE__'))
    WebDriverWait(d,20).until(lambda x:js(x,"return window.__RT76_MASTER_COMPAT_READY__===true || !!window.RT76?.master"))
    js(d,"window.__rt79ButtonErrors=[];window.addEventListener('error',e=>window.__rt79ButtonErrors.push(String(e.error||e.message||'error')));window.addEventListener('unhandledrejection',e=>window.__rt79ButtonErrors.push(String(e.reason||'rejection')));window.confirm=()=>false;window.alert=()=>{}")

def seed(d):
    return js(d,"""const s=RT76.state(),v=s.villages[s.activeVillageId],defs=window.D||window.GAME_DATA||{};
      v.resources=v.resources||{};for(const k of ['wood','clay','iron'])v.resources[k]=999999999;v.resources.lastUpdate=Date.now();
      v.buildQueue=[];v.recruitQueue=[];v.unitResearchQueue=[];v.unitResearch={};
      const bd=defs.buildings||{};for(const k of Object.keys(v.buildings||{})){const mx=Number(bd[k]?.max||30);let lvl=Math.min(Math.max(0,mx-1),10);if(k==='farm'||k==='warehouse')lvl=Math.max(1,mx-1);if(mx<=1)lvl=0;v.buildings[k]=lvl;}
      v.units=v.units||{};for(const k of Object.keys(defs.units||{}))v.units[k]=Math.max(Number(v.units[k]||0),k==='spear'?500:25);
      s.player.crowns=999999;s.player.premium=999999;s.player.icash=999999;s.player.research=s.player.research||{queue:[],completed:[]};s.player.research.queue=[];s.player.research.completed=[];
      const h=s.player.hero;if(h){h.level=Math.max(20,Number(h.level||0));h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(window.HERO_ITEMS)for(const id of Object.keys(HERO_ITEMS))if(!h.story.inventory.includes(id))h.story.inventory.push(id);h.story.equipment=h.story.equipment||{};}
      const other=Object.values(s.villages).find(x=>x.id!==v.id&&x.owner==='barbarian');if(other){other.owner='player';other.ownerName=s.player.name;other.buildings=other.buildings||{};other.buildings.market=Math.max(10,Number(other.buildings.market||0));other.buildings.rally=Math.max(10,Number(other.buildings.rally||0));}
      RT76.save();window.__rt79ButtonBaseline=JSON.stringify(s);return {villages:Object.keys(s.villages).length,buildings:Object.keys(v.buildings||{}).length,units:Object.keys(v.units||{}).length};""")

def restore(d,view):
    info=js(d,"""const raw=window.__rt79ButtonBaseline;if(!raw)return {ok:false,where:'no-baseline'};const fresh=JSON.parse(raw),s=RT76.state();if(!s)return {ok:false,where:'no-state'};Object.assign(s,fresh);window.__rt79ButtonErrors=[];window.confirm=()=>false;window.alert=()=>{};try{document.querySelector('[data-rt79-close]')?.click()}catch(e){};try{RT76.test.setView(arguments[0])}catch(e){return {ok:false,where:'setView',error:String(e?.stack||e)}};return {ok:true,view:String(window.currentView||''),active:s.activeVillageId};""",view)
    if not info.get('ok'): raise RuntimeError(f'restore {view}: {info}')
    time.sleep(.18)

def controls(d):
    return js(d,"""const vis=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};return [...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis).map((e,i)=>({i,text:(e.innerText||e.value||e.getAttribute('aria-label')||'').trim().replace(/\s+/g,' ').slice(0,180),data:{...e.dataset},disabled:!!e.disabled,type:e.type||'',form:e.form?.id||'',cls:String(e.className||'').slice(0,180)}));""")

def prep(d,row,i):
    return js(d,"""const fp=arguments[0],idx=arguments[1],s=RT76.state(),v=s.villages[s.activeVillageId],dd=fp.data||{},defs=window.D||window.GAME_DATA||{};for(const k of ['wood','clay','iron'])v.resources[k]=999999999;v.buildQueue=[];v.recruitQueue=[];v.unitResearchQueue=[];
      if(dd.build&&v.buildings[dd.build]!=null){const mx=Number(defs.buildings?.[dd.build]?.max||30);v.buildings[dd.build]=Math.max(0,Math.min(Number(v.buildings[dd.build]||0),mx-1));}
      if(dd.recruit){v.unitResearch=v.unitResearch||{};v.unitResearch[dd.recruit]=Math.max(1,Number(v.unitResearch[dd.recruit]||0));}
      if(dd.unitResearch){v.unitResearch=v.unitResearch||{};v.unitResearch[dd.unitResearch]=0;}
      if(dd.research&&s.player?.research){s.player.research.queue=[];s.player.research.completed=(s.player.research.completed||[]).filter(x=>x!==dd.research);}
      if(dd.equipHeroItem&&s.player?.hero){const h=s.player.hero;h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(!h.story.inventory.includes(dd.equipHeroItem))h.story.inventory.push(dd.equipHeroItem);}
      s.player.crowns=999999;s.player.premium=999999;s.player.icash=999999;
      const vis=e=>{const z=getComputedStyle(e),r=e.getBoundingClientRect();return z.display!=='none'&&z.visibility!=='hidden'&&Number(z.opacity||1)>0&&r.width>1&&r.height>1};const arr=[...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis),el=arr[idx],form=el?.form;
      if(form){for(const e of [...form.elements]){if(e.disabled||['hidden','submit','button'].includes(e.type))continue;const n=(e.name||e.id||'').toLowerCase();if(e.tagName==='SELECT'){const o=[...e.options].find(o=>!o.disabled&&o.value!=='')||[...e.options].find(o=>!o.disabled);if(o)e.value=o.value;continue}if(e.type==='checkbox'||e.type==='radio'){if(e.required)e.checked=true;continue}if(e.type==='number'||e.type==='range'){let q=Number(e.value);if(!Number.isFinite(q)||q<=0)q=Math.max(1,Number(e.min||1));if(e.max!==''&&Number.isFinite(Number(e.max)))q=Math.min(q,Number(e.max));e.value=String(q);continue}if(e.type==='datetime-local'){const z=new Date(Date.now()+3600000);e.value=new Date(z.getTime()-z.getTimezoneOffset()*60000).toISOString().slice(0,16);continue}if(e.type==='email'){e.value='audit@example.com';continue}if(e.type==='password'){e.value='Audit123!';continue}if(n==='x'||n.endsWith('_x')){e.value='500';continue}if(n==='y'||n.endsWith('_y')){e.value='500';continue}if(n.includes('amount')||n.includes('quant')||n.includes('qty')){e.value='100';continue}if(!e.value)e.value=e.tagName==='TEXTAREA'?'Teste funcional RT79':'Auditoria RT79';}}
      RT76.save();return {exists:!!el,form:form?.id||''};""",row,i)

def click_index(d,i):
    return js(d,"""const idx=arguments[0],vis=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};const a=[...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis),e=a[idx];if(!e)return {ok:false,error:'missing'};try{e.click();return {ok:true}}catch(x){return {ok:false,error:String(x?.stack||x)}};""",i)

def main():
    opts=Options();opts.page_load_strategy='eager';opts.add_argument('--headless=new');opts.add_argument('--no-sandbox');opts.add_argument('--disable-gpu');opts.add_argument('--disable-dev-shm-usage');opts.add_argument('--window-size=1600,1000');opts.set_capability('goog:loggingPrefs',{'browser':'ALL'})
    d=webdriver.Chrome(options=opts);d.set_page_load_timeout(35);d.set_script_timeout(20)
    try:
        start(d);R['seed']=seed(d)
        for view in VIEWS:
            restore(d,view);fps=controls(d);R['views'][view]=len(fps)
            for i,original in enumerate(fps):
                try:
                    restore(d,view);cur=controls(d)
                    if i>=len(cur):R['results'].append({'view':view,'i':i,'text':original.get('text',''),'pass':False,'status':'MISSING_AFTER_RESTORE'});continue
                    row=cur[i]
                    if row.get('disabled'):
                        R['results'].append({'view':view,**row,'pass':True,'status':'DISABLED_EXPECTED','effects':['disabled']});continue
                    prep(d,row,i);before=js(d,"window.__rt79ClickBefore=JSON.stringify(RT76.state());window.__rt79DomBefore=document.querySelector('#app')?.innerHTML||'';return {view:String(window.currentView||'')}")
                    out=click_index(d,i);time.sleep(.035)
                    after=js(d,"""const effects=[],st=JSON.stringify(RT76.state()),dom=document.querySelector('#app')?.innerHTML||'';if(st!==window.__rt79ClickBefore)effects.push('state');if(String(window.currentView||'')!==arguments[0])effects.push('view');if(dom!==window.__rt79DomBefore)effects.push('dom');return {effects,errors:[...(window.__rt79ButtonErrors||[])]};""",before['view'])
                    ok=bool(out.get('ok')) and not after['errors']
                    R['results'].append({'view':view,**row,'pass':ok,'status':'CLICKED' if ok else 'FAIL','effects':after['effects'],'error':out.get('error','') or ' | '.join(after['errors'])})
                except Exception as e:
                    R['results'].append({'view':view,'i':i,'text':original.get('text',''),'pass':False,'status':'HARNESS_EXCEPTION','error':str(e)})
            print(f'buttons {view}: {len(fps)} cumulative={len(R["results"])}',flush=True)
        restore(d,'overview');modal={'available':False,'pass':True};
        if js(d,"return !!document.querySelector('[data-cloud-login]')"):
            modal['available']=True;js(d,"document.querySelector('[data-cloud-login]').click()");time.sleep(.1);has=js(d,"return !!document.querySelector('[data-close-modal]')");modal['pass']=has
            if has:js(d,"document.querySelector('[data-close-modal]').click()")
        R['special_modal']=modal
        restore(d,'settings');reset={'available':False,'pass':True}
        if js(d,"return !!document.querySelector('[data-reset-game]')"):
            reset['available']=True;js(d,"window.confirm=()=>true;document.querySelector('[data-reset-game]').click()");time.sleep(.5);reset['pass']=js(d,"return !!document.querySelector('[data-play-offline]')||!!document.querySelector('#start-form')")
        R['actual_reset']=reset
    except Exception as e:R['fatal']=repr(e)
    finally:
        try:
            logs=d.get_log('browser');R['console_severe']=[x for x in logs if x.get('level')=='SEVERE' and 'favicon' not in x.get('message','').lower()]
        except Exception:R['console_severe']=[]
        try:d.quit()
        except Exception:pass
    R['duration_s']=time.time()-R['started_at'];R['total']=len(R['results']);R['pass']=sum(1 for x in R['results'] if x.get('pass'));R['fail']=R['total']-R['pass'];R['disabled_expected']=sum(1 for x in R['results'] if x.get('status')=='DISABLED_EXPECTED');R['ok']=not R.get('fatal') and R['fail']==0 and R.get('special_modal',{}).get('pass',True) and R.get('actual_reset',{}).get('pass',True) and not R['console_severe']
    (OUT/'RT79_BUTTON_REVALIDATION_CURRENT.json').write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf-8')
    summary={k:R.get(k) for k in ['version','method','duration_s','views','total','pass','fail','disabled_expected','ok','fatal','special_modal','actual_reset','console_severe']};(OUT/'RT79_BUTTON_REVALIDATION_SUMMARY.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(summary,ensure_ascii=False,indent=2));sys.exit(0 if R['ok'] else 1)
if __name__=='__main__':main()
