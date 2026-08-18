from pathlib import Path
import os,json,time,traceback
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

PUBLIC='https://kaalflash12.github.io/reinos-tribais-online/'
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT79_BROWSER_REGRESSION'
OUT.mkdir(parents=True,exist_ok=True)
manifest=[]

def wait(d,t=25):
    WebDriverWait(d,t).until(lambda x:x.execute_script('return document.readyState')=='complete');time.sleep(1.5)
def shot(d,name):
    p=OUT/f'{len(manifest)+1:03d}_{name}.png';d.save_screenshot(str(p));manifest.append({'name':name,'file':p.name});return p
def click(d,sel):
    ok=d.execute_script("const e=document.querySelector(arguments[0]);if(e){e.click();return true}return false",sel)
    if not ok:raise RuntimeError('missing '+sel)
    time.sleep(.5)
def record(name,ok,detail=''):manifest.append({'name':name,'pass':bool(ok),'detail':detail})
def require(cond,msg):
    if not cond:raise AssertionError(msg)

def start_local(d):
    d.get(PUBLIC+'?rt79-browser-audit=1');wait(d)
    require(d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'),'RT79 suite not loaded')
    require(d.execute_script("return !!document.querySelector('[data-rt79-open]')"),'RT79 launcher absent')
    shot(d,'00_entry_rt79_loaded')
    click(d,'[data-play-offline]')
    f=d.find_element(By.CSS_SELECTOR,'#start-form')
    d.execute_script("arguments[0].elements.playerName.value='Auditoria RT79';arguments[0].elements.villageName.value='Aldeia RT79';arguments[0].elements.difficulty.value='normal';arguments[0].elements.mapRadius.value='16';arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit();",f)
    time.sleep(2.5)
    shot(d,'01_overview_desktop')

def base_views(d):
    views=['systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
    for v in views:
        try:click(d,f'[data-view="{v}"]');shot(d,'base_'+v);record('view_'+v,True)
        except Exception as e:record('view_'+v,False,repr(e))

def install_mock(d):
    mock={
      'version':79,
      'settings':{'farm':{'activeTemplate':'A','templates':{'A':{'spear':25},'B':{'axe':40,'light':10},'C':{'light':40,'spy':1}}},'manager':{},'market':{},'scavenge':{},'villageMeta':{}},
      'villages':[{'id':'v1','name':'Aldeia RT79','x':500,'y':500,'points':12345,'resources':{'wood':12000,'clay':11000,'iron':10000},'units':{'spear':250,'axe':300,'light':70},'buildings':{'warehouse':18,'watchtower':1},'build_queue':[],'recruit_queue':[]}],
      'targets':[{'id':'b1','name':'Barbara 501','x':503,'y':502,'points':1000,'owner_kind':'barbarian','buildings':{'wall':2}}],
      'incoming_tactical':[{'id':'i1','class':'noble','risk':95,'source_name':'Inimiga','source_x':490,'source_y':490,'target_name':'Aldeia RT79','total_units':101,'arrives_at':'2026-08-18T15:00:00Z'}],
      'outgoing':[], 'scheduled':[], 'routes':[], 'intel':[], 'logs':[],
      'upcoming_events':[{'id':'e1','name':'Horda RT79','status':'scheduled','starts_at':'2026-08-18T14:00:00Z','ends_at':'2026-08-18T18:00:00Z'}],
      'scavenge_jobs':[]
    }
    js="""
      window.CLOUD=window.CLOUD||{};window.CLOUD.session={access_token:'audit'};window.CLOUD.worldId='w1';window.CLOUD.url='https://audit.invalid';window.CLOUD.key='audit';
      window.__rt79Fetch=window.fetch.bind(window);
      const mock=JSON.parse(arguments[0]);
      window.fetch=async function(u,o){const s=String(u);if(s.includes('/rest/v1/rpc/rt79_world_maintenance'))return new Response(JSON.stringify({version:79}),{status:200,headers:{'Content-Type':'application/json'}});if(s.includes('/rest/v1/rpc/rt79_dashboard'))return new Response(JSON.stringify(mock),{status:200,headers:{'Content-Type':'application/json'}});if(s.includes('/rest/v1/rpc/'))return new Response(JSON.stringify({ok:true}),{status:200,headers:{'Content-Type':'application/json'}});return window.__rt79Fetch(u,o)};
    """
    d.execute_script(js,json.dumps(mock))

def rt79_tabs(d):
    install_mock(d);click(d,'[data-rt79-open]');time.sleep(1.2)
    tabs=['overview','war','farm','market','manager','empire','intel','history']
    for t in tabs:
        click(d,f'[data-rt79-tab="{t}"]');shot(d,'rt79_'+t)
        require(d.execute_script("return document.querySelector('#rt79-overlay')?.classList.contains('open')"),'overlay closed')
        record('rt79_tab_'+t,True)

def mobile(d):
    d.set_window_size(390,844);d.refresh();wait(d)
    require(d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'),'RT79 missing mobile')
    shot(d,'mobile_entry')
    click(d,'[data-play-offline]');time.sleep(.5)
    # existing local save may return to game or start screen; both are allowed, capture current responsive state
    shot(d,'mobile_game_or_start')
    if d.execute_script("return !!document.querySelector('[data-rt79-open]')"):
        install_mock(d);click(d,'[data-rt79-open]');time.sleep(.8);shot(d,'mobile_rt79')

def main():
    opts=Options();opts.add_argument('--headless=new');opts.add_argument('--disable-gpu');opts.add_argument('--no-sandbox');opts.add_argument('--window-size=1600,1000')
    d=webdriver.Edge(options=opts)
    try:
      start_local(d);base_views(d);rt79_tabs(d);mobile(d)
      failures=[x for x in manifest if x.get('pass') is False]
      proof={'pass':not failures,'failures':failures,'screenshots':len([x for x in manifest if x.get('file')]),'manifest':manifest}
      (OUT/'PROVA_BROWSER_RT79.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
      print(json.dumps({'pass':proof['pass'],'screenshots':proof['screenshots'],'failures':len(failures)}))
      if failures:raise SystemExit(2)
    finally:d.quit()
if __name__=='__main__':main()
