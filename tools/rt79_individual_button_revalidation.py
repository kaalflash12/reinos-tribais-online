from pathlib import Path
from playwright.sync_api import sync_playwright
import json, time, sys, os

BASE=os.environ.get('RT79_BUTTON_URL','http://127.0.0.1:8765/index.html?rt79buttons=1')
OUT=Path('RT79_BUTTON_REVALIDATION');OUT.mkdir(exist_ok=True)
VIEWS=['overview','systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
R={'method':'literal visible button instances clicked individually from restored RT79.1 baseline state; disabled controls recorded separately; reset confirmation cancelled in matrix and verified separately','version':'RT79.1','views':{},'results':[],'page_errors':[],'started_at':time.time()}

def start(page):
    page.goto(BASE,wait_until='domcontentloaded',timeout=45000);page.wait_for_timeout(650)
    off=page.locator('[data-play-offline]').first
    if off.count() and off.is_visible(): off.click();page.wait_for_timeout(250)
    f=page.locator('#start-form')
    if f.count() and f.is_visible():
        f.locator('[name=playerName]').fill('Auditoria Individual RT79')
        f.locator('[name=villageName]').fill('Aldeia Auditoria RT79')
        try:f.locator('[name=difficulty]').select_option('normal')
        except:pass
        try:f.locator('[name=mapRadius]').select_option('16')
        except:pass
        f.locator('button[type=submit],button:not([type])').last.click()
    page.wait_for_selector('.game-shell',timeout=20000)
    page.wait_for_function('window.RT76&&RT76.state&&RT76.state()?.activeVillageId',timeout=20000)
    page.wait_for_timeout(300)
    page.evaluate('''()=>{
      window.confirm=()=>false; window.alert=()=>{};
      window.__rt79ButtonErrors=[];
      window.addEventListener('error',e=>window.__rt79ButtonErrors.push(String(e.error||e.message||'error')));
      window.addEventListener('unhandledrejection',e=>window.__rt79ButtonErrors.push(String(e.reason||'rejection')));
    }''')

def seed(page):
    return page.evaluate('''()=>{
      const s=RT76.state(),v=s.villages[s.activeVillageId],defs=(window.D||window.GAME_DATA||{});
      v.resources=v.resources||{};for(const k of ['wood','clay','iron'])v.resources[k]=999999999;v.resources.lastUpdate=Date.now();
      v.buildQueue=[];v.recruitQueue=[];v.unitResearchQueue=[];v.unitResearch=v.unitResearch||{};
      const bd=defs.buildings||{};
      for(const k of Object.keys(v.buildings||{})){
        const mx=Number(bd[k]?.max||30);let lvl=Math.min(12,Math.max(0,mx-1));
        if(k==='farm'||k==='warehouse')lvl=Math.max(1,mx-1);
        if(mx<=1)lvl=0;v.buildings[k]=lvl;
      }
      v.units=v.units||{};for(const k of Object.keys(defs.units||{}))v.units[k]=Math.max(Number(v.units[k]||0),k==='spear'?500:25);
      s.player=s.player||{};s.player.crowns=999999;s.player.premium=999999;s.player.icash=999999;
      s.player.research=s.player.research||{completed:[],queue:[]};s.player.research.completed=[];s.player.research.queue=[];
      const h=s.player.hero;if(h){try{ensureHeroStoryState(h)}catch(e){};h.level=Math.max(20,Number(h.level||0));h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(window.HERO_ITEMS)for(const id of Object.keys(HERO_ITEMS))if(!h.story.inventory.includes(id))h.story.inventory.push(id);h.story.equipment=h.story.equipment||{};}
      const other=Object.values(s.villages).find(x=>x.id!==v.id&&x.owner==='barbarian');if(other){other.owner='player';other.ownerName=s.player.name;other.buildings=other.buildings||{};other.buildings.market=Math.max(10,Number(other.buildings.market||0));other.buildings.rally=Math.max(10,Number(other.buildings.rally||0));}
      try{RT76.save()}catch(e){};window.__RT79_BUTTON_BASELINE=JSON.stringify(s);return {villages:Object.keys(s.villages).length,buildings:Object.keys(v.buildings||{}).length,units:Object.keys(v.units||{}).length};
    }''')

def restore(page,view):
    page.evaluate('''(view)=>{
      try{document.querySelector('[data-rt79-close]')?.click()}catch(e){}
      try{if(typeof modalHtml!=='undefined')modalHtml=''}catch(e){}
      const fresh=JSON.parse(window.__RT79_BUTTON_BASELINE),s=RT76.state();for(const k of Object.keys(s))delete s[k];Object.assign(s,fresh);window.__rt79ButtonErrors=[];
      try{currentView=view;renderAll()}catch(e){try{RT76.test.setView(view)}catch(_){} }
    }''',view);page.wait_for_timeout(35)

def visible_buttons(page):
    return page.evaluate('''()=>{
      const vis=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};
      return [...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis).map((e,i)=>({i,text:(e.innerText||e.value||e.getAttribute('aria-label')||'').trim().replace(/\\s+/g,' ').slice(0,180),data:{...e.dataset},disabled:!!e.disabled,type:e.type||'',form:e.form?.id||'',cls:String(e.className||'').slice(0,220)}));
    }''')

def prep(page,fp,index):
    page.evaluate('''(p)=>{
      const fp=p.fp,s=RT76.state(),v=s.villages[s.activeVillageId],d=fp.data||{},defs=(window.D||window.GAME_DATA||{});
      for(const k of ['wood','clay','iron'])v.resources[k]=999999999;v.buildQueue=[];v.recruitQueue=[];v.unitResearchQueue=[];
      if(d.build&&v.buildings[d.build]!=null){const mx=Number(defs.buildings?.[d.build]?.max||30);v.buildings[d.build]=Math.max(0,Math.min(Number(v.buildings[d.build]||0),mx-1));}
      if(d.recruit){v.unitResearch=v.unitResearch||{};v.unitResearch[d.recruit]=Math.max(1,Number(v.unitResearch[d.recruit]||0));}
      if(d.unitResearch){v.unitResearch=v.unitResearch||{};v.unitResearch[d.unitResearch]=0;v.unitResearchQueue=[];}
      if(d.research&&s.player?.research){s.player.research.queue=[];s.player.research.completed=(s.player.research.completed||[]).filter(x=>x!==d.research);}
      if(d.equipHeroItem&&s.player?.hero){const h=s.player.hero;h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(!h.story.inventory.includes(d.equipHeroItem))h.story.inventory.push(d.equipHeroItem);}
      s.player.crowns=999999;s.player.premium=999999;s.player.icash=999999;
      const form=document.getElementById(fp.form)||document.querySelectorAll('button,input[type=submit],input[type=button]')[p.index]?.form;
      if(form){for(const e of [...form.elements]){if(e.disabled||e.type==='hidden'||e.type==='submit'||e.type==='button')continue;const n=(e.name||e.id||'').toLowerCase();if(e.tagName==='SELECT'){const o=[...e.options].find(x=>!x.disabled&&x.value!=='')||[...e.options].find(x=>!x.disabled);if(o)e.value=o.value;continue}if(e.type==='checkbox'||e.type==='radio'){if(e.required)e.checked=true;continue}if(e.type==='number'||e.type==='range'){let q=Number(e.value);if(!Number.isFinite(q)||q<=0)q=Math.max(1,Number(e.min||1));if(Number.isFinite(Number(e.max))&&e.max!=='')q=Math.min(q,Number(e.max));e.value=String(q);continue}if(e.type==='datetime-local'){const z=new Date(Date.now()+3600000);e.value=new Date(z.getTime()-z.getTimezoneOffset()*60000).toISOString().slice(0,16);continue}if(e.type==='email'){e.value='audit@example.com';continue}if(e.type==='password'){e.value='Audit123!';continue}if(n.includes('x')){e.value='500';continue}if(n.includes('y')){e.value='500';continue}if(n.includes('amount')||n.includes('quant')||n.includes('qty')){e.value='100';continue}if(!e.value)e.value=n.includes('message')||e.tagName==='TEXTAREA'?'Teste funcional RT79':'Auditoria RT79';}}
      }
      try{RT76.save()}catch(e){}
    }''',{'fp':fp,'index':index})

def click_one(page,view,index,fp):
    restore(page,view); prep(page,fp,index);page.wait_for_timeout(12)
    before=page.evaluate('''()=>{window.__rt79BeforeState=JSON.stringify(RT76.state());window.__rt79BeforeDom=document.querySelector('#app')?.innerHTML||document.body.innerHTML;return {view:String(window.currentView||''),errors:(window.__rt79ButtonErrors||[]).length}}''')
    cur=visible_buttons(page)
    if index>=len(cur):return {'view':view,'i':index,**fp,'pass':False,'status':'MISSING_AFTER_RESET','effects':[]}
    nowfp=cur[index]
    if nowfp['disabled']:
        return {'view':view,'i':index,**nowfp,'pass':True,'status':'DISABLED_EXPECTED','effects':['disabled']}
    err=''
    try:
        page.evaluate('''(i)=>{const vis=e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>1&&r.height>1};const a=[...document.querySelectorAll('button,input[type=submit],input[type=button]')].filter(vis);if(!a[i])throw Error('button index missing');a[i].click()}''',index)
        page.wait_for_timeout(28)
    except Exception as e:err=repr(e)
    after=page.evaluate('''()=>{const st=JSON.stringify(RT76.state()),dom=document.querySelector('#app')?.innerHTML||document.body.innerHTML;const effects=[];if(st!==window.__rt79BeforeState)effects.push('state');if(String(window.currentView||'')!==arguments[0])effects.push('view');if(dom!==window.__rt79BeforeDom)effects.push('dom');return {effects,errors:[...(window.__rt79ButtonErrors||[])]}}''',before['view'])
    ok=not err and len(after['errors'])==0
    return {'view':view,'i':index,**nowfp,'pass':ok,'status':'CLICKED' if ok else 'FAIL','effects':after['effects'],'error':err or (' | '.join(after['errors']) if after['errors'] else '')}

def matrix(page):
    seedinfo=seed(page);R['seed']=seedinfo
    for view in VIEWS:
        restore(page,view);fps=visible_buttons(page);R['views'][view]={'visible_instances':len(fps)}
        for i,fp in enumerate(fps):R['results'].append(click_one(page,view,i,fp))
        print(view,len(fps),'cumulative',len(R['results']),flush=True)

def specialized_modal(page):
    restore(page,'overview');loc=page.locator('[data-cloud-login]').first
    rec={'name':'open_then_close_modal','pass':False}
    if loc.count() and loc.is_visible():
        loc.click();page.wait_for_timeout(80);close=page.locator('[data-close-modal]').first
        if close.count() and close.is_visible():close.click();page.wait_for_timeout(30);rec['pass']=page.locator('[data-close-modal]').count()==0 or not page.locator('[data-close-modal]').first.is_visible();rec['status']='SPECIALIZED_OPEN_THEN_CLOSE_PASS' if rec['pass'] else 'FAIL'
    R['specialized_modal']=rec

def actual_reset(page):
    restore(page,'settings');page.evaluate('window.confirm=()=>true');loc=page.locator('[data-reset-game]').first
    rec={'name':'actual_reset_game','available':bool(loc.count()),'pass':True}
    if loc.count() and loc.is_visible():
        try:loc.click();page.wait_for_timeout(500);rec['pass']=page.locator('[data-play-offline]').count()>0 or page.locator('#start-form').count()>0
        except Exception as e:rec={'name':'actual_reset_game','available':True,'pass':False,'error':repr(e)}
    R['actual_reset']=rec

def main():
    with sync_playwright() as pw:
        b=pw.chromium.launch(headless=True);p=b.new_page(viewport={'width':1600,'height':1000});p.on('pageerror',lambda e:R['page_errors'].append(str(e)))
        start(p);matrix(p);specialized_modal(p);actual_reset(p);b.close()
    R['finished_at']=time.time();R['duration_s']=R['finished_at']-R['started_at'];R['total']=len(R['results']);R['pass']=sum(1 for x in R['results'] if x.get('pass'));R['fail']=R['total']-R['pass'];R['disabled_expected']=sum(1 for x in R['results'] if x.get('status')=='DISABLED_EXPECTED');R['ok']=R['fail']==0 and R.get('specialized_modal',{}).get('pass',False) and R.get('actual_reset',{}).get('pass',False) and not R['page_errors']
    (OUT/'RT79_BUTTON_INDIVIDUAL_CURRENT.json').write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf-8')
    summary={k:R[k] for k in ['version','method','total','pass','fail','disabled_expected','duration_s','ok']};summary['view_counts']={k:v['visible_instances'] for k,v in R['views'].items()};summary['specialized_modal']=R.get('specialized_modal');summary['actual_reset']=R.get('actual_reset');summary['page_errors']=R['page_errors'];(OUT/'RESUMO.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(summary,ensure_ascii=False,indent=2));sys.exit(0 if R['ok'] else 1)
if __name__=='__main__':main()
