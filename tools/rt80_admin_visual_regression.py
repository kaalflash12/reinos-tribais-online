from pathlib import Path
import json, os, time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
ROOT=Path(__file__).resolve().parents[1]
AUDIT_HTML=ROOT/'rt80_admin_audit.html'
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_ADMIN_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[],'tabs':[]}

TABS=[
 ('overview','OVERVIEW'),('worlds','WORLDS'),('players','PLAYERS'),('villages','VILLAGES'),
 ('mapops','MAP'),('events','EVENTS'),('ranked','RANKED'),('combat','COMBAT'),('market','MARKET'),
 ('tribes','TRIBES'),('comms','COMMS'),('rewards','REWARDS'),('database','DATABASE'),
 ('audit','AUDIT'),('security','SECURITY')
]

MOCK={
 'version':80,'generated_at':'2026-08-19T20:30:00Z',
 'worlds':[{'id':'w1','name':'Mundo Auditoria RT80','status':'open','is_active':True,'max_players':100,'season_number':3,
            'settings':{'worldSpeed':8,'unitSpeed':3,'mapRadius':35,'resourceMultiplier':1,'marketMultiplier':1,'archers':True,'militia':True,'church':True,'watchtower':True,'flags':True,'scavenging':True,'eventSystem':True,'monstersEnabled':True}}],
 'players':[{'world_id':'w1','user_id':'u1','player_name':'Governante Auditoria','email':'audit@example.test','points':12450,'crowns':800,'academy_coins':12,'village_count':1,'is_suspended':False,'last_seen_at':'2026-08-19T20:25:00Z','last_sign_in_at':'2026-08-19T20:20:00Z','save_updated_at':'2026-08-19T20:25:00Z','control':{'status':'active','note':''},'hero':{'level':5},'inventory':{},'flags_inventory':{},'premium':{},'research':{}}],
 'villages':[{'id':'v1','world_id':'w1','name':'Fortaleza Auditoria','x':500,'y':500,'points':12450,'loyalty':100,'owner_kind':'player','owner_user_id':'u1','owner_name':'Governante Auditoria','tribe_name':'Auditores','resources':{'wood':50000,'clay':42000,'iron':38000},'units':{},'buildings':{},'militia_called':False}],
 'nodes':[],
 'events':[{'id':'e1','world_id':'w1','name':'Festival de Auditoria','template_key':'festival','category':'seasonal','status':'active','starts_at':'2026-08-19T19:00:00Z','ends_at':'2026-08-20T19:00:00Z','config':{'multiplier':1.25},'rewards':{}}],
 'monsters':[{'id':'m1','world_id':'w1','name':'Colosso de Auditoria','template_key':'colossus','monster_type':'boss','x':504,'y':497,'level':8,'hp':72000,'max_hp':100000,'status':'active','reward':{}}],
 'eventTemplates':[],'monsterTemplates':[],
 'commands':[],'attacks':[],'onlineSupports':[],
 'tribes':[{'id':'t1','world_id':'w1','name':'Auditores','tag':'AUD','points':12450,'member_count':1}],
 'tribeMembers':[{'tribe_id':'t1','user_id':'u1','role':'leader'}],
 'offers':[],'messages':[],'reports':[],
 'entitlements':[{'id':'ent1','world_id':'w1','user_id':'u1','kind':'title','code':'auditor','name':'Auditor RT80','active':True}],
 'rtWorldEvents':[],'eventProgress':[],'eventRewards':[],
 'auditLog':[{'id':'a1','admin_username':'auditoria','action':'player.inspect','entity_type':'player','entity_id':'u1','created_at':'2026-08-19T20:24:00Z','metadata':{'source':'visual-test'}}],
 'seasons':[{'id':'s1','world_id':'w1','name':'Temporada Auditoria','status':'active','starts_at':'2026-08-01T00:00:00Z','ends_at':'2026-09-01T00:00:00Z'}],
 'ratings':[{'season_id':'s1','user_id':'u1','rating':1280,'wins':12,'losses':4,'matches':16,'streak':3}],
 'matches':[],
 'adminSessions':[{'id':'sess-audit','admin_id':'adm1','created_at':'2026-08-19T20:00:00Z','last_seen_at':'2026-08-19T20:25:00Z','expires_at':'2026-08-20T20:00:00Z'}],
 'adminAccounts':[{'id':'adm1','username':'auditoria','display_name':'Administrador Auditoria','role':'superadmin','active':True,'last_login_at':'2026-08-19T20:00:00Z'}],
 'monsterHits':[],
 'worldStats':[{'world_id':'w1','players':1,'online':1,'villages':1,'nodes':0,'monsters':1,'events':1,'commands':0,'tribes':1,'offers':0}],
 'dbCounts':{'worlds':1,'players':1,'villages':1,'events':1,'monsters':1,'audit_logs':1}
}


def prepare_html():
    src=(ROOT/'index.html').read_text(encoding='utf-8')
    old="try{const sr=await adminSupportRequest('support_list');data.onlineSupports=Array.isArray(sr?.supports)?sr.supports:[]}catch{data.onlineSupports=[]}"
    new="data.onlineSupports=Array.isArray(data.onlineSupports)?data.onlineSupports:[]"
    if old not in src:
        raise RuntimeError('admin support patch anchor not found')
    src=src.replace(old,new,1)
    anchor="window.addEventListener('beforeunload', () => saveState(true));"
    expose="window.__RT80_ADMIN_AUDIT__={renderIntegratedAdmin,RTADMIN};\n\n  "+anchor
    if anchor not in src:
        raise RuntimeError('admin audit exposure anchor not found')
    src=src.replace(anchor,expose,1)
    AUDIT_HTML.write_text(src,encoding='utf-8')


def check(d,name,js,timeout=20):
    WebDriverWait(d,timeout).until(lambda x:x.execute_script(js))
    ok=bool(d.execute_script(js))
    proof['checks'].append({'name':name,'pass':ok})
    if not ok: raise AssertionError(name)


def shot(d,name):
    path=OUT/f'{len(proof["screenshots"])+1:02d}_{name}.png'
    d.save_screenshot(str(path));proof['screenshots'].append(path.name)


def close_modals(d):
    d.execute_script("document.querySelectorAll('.rt64-modal,.rt60-admin-modal').forEach(x=>x.remove())")
    time.sleep(.2)


def open_modal(d,selector,name):
    d.execute_script("document.querySelector(arguments[0])?.click()",selector)
    WebDriverWait(d,10).until(lambda x:x.execute_script("return !!document.querySelector('.rt64-modal,.rt60-admin-modal')"))
    check(d,f'{name}: modal marked by RT80 runtime',"return !!document.querySelector('[data-rt80-admin-modal=\"1\"]')")
    check(d,f'{name}: dialog semantics',"return document.querySelector('.rt64-modal,.rt60-admin-modal')?.getAttribute('role')==='dialog'")
    shot(d,name)
    close_modals(d)


def main():
    prepare_html()
    opts=Options();opts.page_load_strategy='eager'
    opts.add_argument('--headless=new');opts.add_argument('--disable-gpu');opts.add_argument('--no-sandbox');opts.add_argument('--window-size=1600,1000');opts.add_argument('--disable-dev-shm-usage')
    d=webdriver.Edge(options=opts)
    try:
        d.get(BASE+'rt80_admin_audit.html?rt80-admin-audit=1')
        WebDriverWait(d,25).until(lambda x:x.execute_script("return !!window.__RT80_ADMIN_AUDIT__"))
        result=d.execute_async_script("""
          const mock=arguments[0],done=arguments[arguments.length-1];
          (async()=>{try{
            const a=window.__RT80_ADMIN_AUDIT__;
            a.RTADMIN.token='audit-only';a.RTADMIN.username='auditoria';a.RTADMIN.info={username:'auditoria',role:'superadmin'};
            a.RTADMIN.ui={tab:'overview',worldId:'w1',mapX:500,mapY:500};
            await a.renderIntegratedAdmin(mock,true);
            done({ok:true});
          }catch(e){done({ok:false,error:String(e?.stack||e)})}})();
        """,MOCK)
        if not result.get('ok'): raise RuntimeError(result.get('error'))
        check(d,'admin shell rendered',"return !!document.querySelector('.rt60-admin-shell')")
        check(d,'RT80 admin runtime ready',"return document.querySelector('.rt60-admin-shell')?.dataset.rt80AdminReady==='1'")
        check(d,'15 admin tabs exist',"return document.querySelectorAll('[data-admin-tab]').length===15")
        check(d,'admin header has no RT10-RT79 branding',"return !/\\bRT(?:[1-7]\\d)(?:\\.\\d+)?\\b/i.test(document.querySelector('.rt60-admin-top')?.innerText||'')")
        check(d,'admin tables get scoped headers',"return [...document.querySelectorAll('.rt60-admin-shell th')].every(x=>x.getAttribute('scope')==='col')")

        for tab,label in TABS:
            d.execute_script("document.querySelector('[data-admin-tab=\"'+arguments[0]+'\"]')?.click()",tab)
            WebDriverWait(d,10).until(lambda x,t=tab:x.execute_script("return !!document.querySelector('[data-admin-panel=\"'+arguments[0]+'\"]:not(.hidden)')",t))
            check(d,f'{tab}: panel visible',"const p=document.querySelector('[data-admin-panel=\"'+arguments[0]+'\"]');return !!p&&getComputedStyle(p).display!=='none'",timeout=10)
            check(d,f'{tab}: no horizontal body overflow',"return document.documentElement.scrollWidth<=window.innerWidth+16",timeout=10)
            proof['tabs'].append(tab);shot(d,f'ADMIN_{label}')

        # Real editor modals, opened via the real delegated click handlers. No submit is performed.
        d.execute_script("document.querySelector('[data-admin-tab=\"players\"]')?.click()")
        time.sleep(.4);open_modal(d,'[data-rt64-edit-player]','ADMIN_MODAL_PLAYER')
        d.execute_script("document.querySelector('[data-admin-tab=\"villages\"]')?.click()")
        time.sleep(.4);open_modal(d,'[data-rt64-edit-village]','ADMIN_MODAL_VILLAGE')
        d.execute_script("document.querySelector('[data-admin-tab=\"events\"]')?.click()")
        time.sleep(.4);open_modal(d,'[data-rt64-edit-event]','ADMIN_MODAL_EVENT')
        open_modal(d,'[data-rt64-edit-monster]','ADMIN_MODAL_MONSTER')

        d.set_window_size(430,932);time.sleep(.6)
        d.execute_script("document.querySelector('[data-admin-tab=\"overview\"]')?.click()")
        time.sleep(.4)
        check(d,'admin mobile no horizontal body overflow',"return document.documentElement.scrollWidth<=window.innerWidth+8")
        check(d,'admin mobile nav horizontal and visible',"const n=document.querySelector('.rt60-admin-nav');return !!n&&getComputedStyle(n).display==='flex'&&n.getBoundingClientRect().height>35")
        shot(d,'ADMIN_MOBILE_OVERVIEW')
        proof['pass']=True
    except Exception as e:
        proof['error']=repr(e)
        try: shot(d,'ADMIN_FAILURE')
        except Exception: pass
        raise
    finally:
        try: proof['console']=d.get_log('browser')
        except Exception: proof['console']=[]
        (OUT/'PROVA_RT80_ADMIN_VISUAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
        try:AUDIT_HTML.unlink()
        except Exception:pass

if __name__=='__main__':main()
