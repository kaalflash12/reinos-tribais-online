import json
import os
import time
import urllib.error
import urllib.request
import uuid
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.edge.options import Options as EdgeOptions
from selenium.webdriver.support.ui import WebDriverWait
import rt79_chrome_fast_regression as r

API_BASE='https://reino-tribal-api.mestrederpg35.deno.net'
API_REINO=API_BASE+'/api/reino'
PUBLIC_ORIGIN='https://kaalflash12.github.io'
PUBLIC_URL='https://kaalflash12.github.io/reinos-tribais-online/'
LEGACY_ORIGIN='https://rlyiwlwzrdgvcwawrnpl.supabase.co'
WORLD_ID='d5a546fb-316d-4332-ae92-1886d80b07df'
SESSION_KEY='reinos_tribais_supabase_session_v60_browser'


def api_post(payload, token=''):
    headers={
        'Origin':PUBLIC_ORIGIN,
        'Accept':'application/json',
        'Content-Type':'application/json'
    }
    if token:
        headers['Authorization']='Bearer '+token
    req=urllib.request.Request(
        API_REINO,
        data=json.dumps(payload,separators=(',',':')).encode('utf-8'),
        headers=headers,
        method='POST'
    )
    try:
        with urllib.request.urlopen(req,timeout=60) as res:
            body=res.read().decode('utf-8')
            return res.status,json.loads(body or '{}')
    except urllib.error.HTTPError as e:
        body=e.read().decode('utf-8','replace')
        raise RuntimeError(f'API {payload.get("action")} HTTP {e.code}: {body[:500]}') from e


def provision_mobile_player():
    suffix=uuid.uuid4().hex[:16]
    identifier=f'rt80-mobile-{suffix}@example.invalid'
    username=f'm_{suffix}'
    password='RT80!'+uuid.uuid4().hex+'x'
    status,reg=api_post({'action':'register','email':identifier,'username':username,'password':password})
    r.rec('mobile provision register',200 <= int(status) < 300 and bool(reg.get('access_token')) and str((reg.get('user') or {}).get('role'))=='player')
    token=str(reg.get('access_token') or '')
    status,joined=api_post({'action':'join_world','world_id':WORLD_ID,'player_name':username},token)
    r.rec('mobile provision Mundo 1',200 <= int(status) < 300 and bool(joined.get('ok')) and str((joined.get('world') or {}).get('id'))==WORLD_ID)
    return identifier,password,username


def visible_click_view(d, view):
    return r.js(d, """
      const all=[...document.querySelectorAll('[data-view="'+arguments[0]+'"]')];
      for(const e of all){
        let cs=getComputedStyle(e),b=e.getBoundingClientRect();
        if(cs.display==='none'||cs.visibility==='hidden'||Number(cs.opacity)===0||b.width<1||b.height<1)continue;
        e.scrollIntoView({block:'nearest',inline:'nearest'});
        cs=getComputedStyle(e);b=e.getBoundingClientRect();
        if(cs.display==='none'||cs.visibility==='hidden'||Number(cs.opacity)===0||b.width<1||b.height<1)continue;
        e.click();
        return true;
      }
      return false;
    """, view)


def emulate_mobile(d, width=390, height=844):
    d.execute_cdp_cmd('Emulation.setDeviceMetricsOverride', {
        'mobile': True,
        'width': width,
        'height': height,
        'deviceScaleFactor': 1,
        'screenWidth': width,
        'screenHeight': height
    })
    d.execute_cdp_cmd('Emulation.setTouchEmulationEnabled', {
        'enabled': True,
        'maxTouchPoints': 5
    })
    time.sleep(.15)


def mobile_gameplay_e2e(d):
    emulate_mobile(d)
    viewport=r.js(d,"return {w:innerWidth,h:innerHeight,sw:document.documentElement.scrollWidth,sh:document.documentElement.scrollHeight}")
    r.rec('mobile viewport 390',380 <= int(viewport['w']) <= 400,json.dumps(viewport))
    r.rec('mobile viewport height',int(viewport['h']) >= 800,json.dumps(viewport))
    r.rec('mobile suite',r.js(d,'return !!window.__RT79_STRATEGY_SUITE__'))
    r.js(d,"document.querySelector('[data-rt79-close]')?.click()")

    for view in ['overview','buildings','recruit','research','map','market','reports','settings']:
        r.rec('mobile view '+view,visible_click_view(d,view))
        time.sleep(.06)

    r.js(d,"""
      const s=RT76.state(),v=s.villages[s.activeVillageId];
      v.resources.wood=v.resources.clay=v.resources.iron=999999;
      v.buildQueue=[];
      for(const k of Object.keys(v.buildings||{}))v.buildings[k]=Math.max(Number(v.buildings[k]||0),1);
      RT76.save();
    """)
    visible_click_view(d,'buildings')
    before=r.js(d,"const s=RT76.state(),v=s.villages[s.activeVillageId];return v.buildQueue.length")
    key=r.js(d,"""
      const all=[...document.querySelectorAll('[data-build]:not([disabled])')];
      for(const e of all){
        let cs=getComputedStyle(e),b=e.getBoundingClientRect();
        if(cs.display==='none'||cs.visibility==='hidden'||b.width<1||b.height<1)continue;
        e.scrollIntoView({block:'center',inline:'nearest'});
        cs=getComputedStyle(e);b=e.getBoundingClientRect();
        if(cs.display==='none'||cs.visibility==='hidden'||b.width<1||b.height<1)continue;
        e.click();return e.dataset.build||'';
      }
      return '';
    """)
    after=r.js(d,"const s=RT76.state(),v=s.villages[s.activeVillageId];return v.buildQueue.length")
    r.rec('mobile build queue',bool(key) and after>before,key)

    visible_click_view(d,'overview')
    shell=r.js(d,"""
      const e=document.querySelector('.game-shell');if(!e)return null;
      const b=e.getBoundingClientRect();return {left:b.left,right:b.right,width:b.width,inner:innerWidth};
    """)
    r.rec('mobile game shell rendered',bool(shell),json.dumps(shell))
    r.rec('mobile primary launcher visible',r.js(d,"""
      const e=document.querySelector('[data-rt79-open]');if(!e)return false;
      const b=e.getBoundingClientRect(),c=getComputedStyle(e);return c.display!=='none'&&c.visibility!=='hidden'&&b.width>0&&b.height>0;
    """))

    name=r.js(d,"RT76.save();return RT76.state().player.name")
    before_path=r.OUT/'RT80_MOBILE_E2E_BEFORE_RELOAD.png'
    r.rec('mobile screenshot before reload',d.save_screenshot(str(before_path)),str(before_path))
    r.nav(d,'?mobile-e2e=reload')
    emulate_mobile(d)
    WebDriverWait(d,25).until(lambda x:r.js(x,'return !!window.__RT79_STRATEGY_SUITE__'))
    r.click(d,'[data-play-offline]')
    WebDriverWait(d,12).until(lambda x:r.js(x,'return !!window.RT76?.state?.()?.activeVillageId'))
    loaded=r.js(d,"return RT76.state()?.player?.name||''")
    r.rec('mobile save reload',loaded==name,f'{name} -> {loaded}')
    after_path=r.OUT/'RT80_MOBILE_E2E_AFTER_RELOAD.png'
    r.rec('mobile screenshot after reload',d.save_screenshot(str(after_path)),str(after_path))
    return {'pass':True,'viewport':viewport,'player':loaded,'build_key':key}


def mobile_online_e2e(d):
    explicit=os.environ.get('RT79_REQUIRE_MOBILE_ONLINE','').strip()
    required=(explicit=='1') if explicit else r.URL.startswith(PUBLIC_URL)
    identifier=os.environ.get('RT79_MOBILE_IDENTIFIER','').strip()
    password=os.environ.get('RT79_MOBILE_PASSWORD','')
    username=''
    if required and (not identifier or not password):
        identifier,password,username=provision_mobile_player()
    if not identifier or not password:
        r.rec('mobile online auth skipped',not required,'local/PR target')
        return {'pass':not required,'skipped':True}

    emulate_mobile(d)
    r.nav(d,'?mobile-online-e2e=1')
    emulate_mobile(d)
    WebDriverWait(d,25).until(lambda x:r.js(x,'return !!window.ReinoTribalTurso'))
    online_viewport=r.js(d,"return {w:innerWidth,h:innerHeight,sw:document.documentElement.scrollWidth}")
    r.rec('mobile online viewport 390',380 <= int(online_viewport['w']) <= 400,json.dumps(online_viewport))
    api=r.js(d,"return window.ReinoTribalTurso?.apiBase||''")
    r.rec('mobile public API configured',api==API_BASE,api)
    r.rec('mobile Turso bridge active',r.js(d,"return !!window.__RT_TURSO_BRIDGE__ && !!window.__RT85_AUTH_BRIDGE__"))
    r.rec('mobile legacy network blocked',r.js(d,"return window.ReinoTribalTurso?.blockLegacySupabase===true"))

    opened=r.js(d,"""
      const e=document.querySelector('[data-cloud-login]');
      if(!e)return false;e.scrollIntoView({block:'center'});e.click();return true;
    """)
    r.rec('mobile open online login',opened)
    WebDriverWait(d,12).until(lambda x:x.find_element(By.CSS_SELECTOR,'#rt18-login-form'))
    submitted=r.js(d,"""
      const f=document.querySelector('#rt18-login-form');if(!f)return false;
      f.elements.email.value=arguments[0];f.elements.password.value=arguments[1];
      f.requestSubmit();return true;
    """,identifier,password)
    r.rec('mobile submit online login',submitted)

    def has_session(x):
        return r.js(x,"""
          try{
            const s=window.CLOUD?.session||JSON.parse(sessionStorage.getItem(arguments[0])||'null');
            return !!(s?.access_token && (window.CLOUD?.user?.id || s?.user?.id));
          }catch{return false}
        """,SESSION_KEY)
    WebDriverWait(d,30).until(has_session)
    r.rec('mobile online session',has_session(d))

    health=d.execute_async_script("""
      const done=arguments[arguments.length-1];
      window.ReinoTribalTurso.health().then(x=>done({ok:true,data:x})).catch(e=>done({ok:false,error:String(e?.message||e)}));
    """)
    r.rec('mobile production health',bool(health.get('ok')),json.dumps(health,ensure_ascii=False))

    marker='mobile-'+str(int(time.time()*1000))
    save=d.execute_async_script("""
      const legacy=arguments[0],world=arguments[1],marker=arguments[2],sessionKey=arguments[3],done=arguments[arguments.length-1];
      let s=null;try{s=window.CLOUD?.session||JSON.parse(sessionStorage.getItem(sessionKey)||'null')}catch{}
      const token=s?.access_token||'';
      fetch(legacy+'/rest/v1/game_saves',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({world_id:world,state:{mobile_e2e_marker:marker,probe:'public-mobile-browser'}})})
        .then(async z=>done({status:z.status,data:await z.json().catch(()=>null)})).catch(e=>done({status:0,error:String(e?.message||e)}));
    """,LEGACY_ORIGIN,WORLD_ID,marker,SESSION_KEY)
    r.rec('mobile online save',200 <= int(save.get('status',0)) < 300,json.dumps(save,ensure_ascii=False))

    loaded=d.execute_async_script("""
      const legacy=arguments[0],world=arguments[1],sessionKey=arguments[2],done=arguments[arguments.length-1];
      let s=null;try{s=window.CLOUD?.session||JSON.parse(sessionStorage.getItem(sessionKey)||'null')}catch{}
      const token=s?.access_token||'';
      fetch(legacy+'/rest/v1/game_saves?world_id=eq.'+encodeURIComponent(world),{headers:{'Authorization':'Bearer '+token}})
        .then(async z=>done({status:z.status,data:await z.json().catch(()=>null)})).catch(e=>done({status:0,error:String(e?.message||e)}));
    """,LEGACY_ORIGIN,WORLD_ID,SESSION_KEY)
    rows=loaded.get('data') or []
    row=rows[0] if isinstance(rows,list) and rows else (rows if isinstance(rows,dict) else {})
    state=row.get('state') or row.get('state_json') or {}
    r.rec('mobile online load',200 <= int(loaded.get('status',0)) < 300 and isinstance(state,dict) and state.get('mobile_e2e_marker')==marker,json.dumps(loaded,ensure_ascii=False))
    online_path=r.OUT/'RT80_MOBILE_ONLINE_TURSO_E2E.png'
    r.rec('mobile online screenshot',d.save_screenshot(str(online_path)),str(online_path))
    return {'pass':True,'marker':marker,'api':api,'viewport':online_viewport,'save_status':save.get('status'),'load_status':loaded.get('status'),'player':username or identifier}


def main():
    opts=EdgeOptions()
    opts.page_load_strategy='eager'
    opts.add_argument('--headless=new')
    opts.add_argument('--disable-gpu')
    opts.add_argument('--window-size=1600,1000')
    opts.add_argument('--no-first-run')
    opts.add_argument('--disable-dev-shm-usage')
    opts.add_argument('--ignore-certificate-errors')
    opts.add_experimental_option('prefs',{'profile.managed_default_content_settings.images':2})
    d=webdriver.Edge(options=opts)
    d.set_page_load_timeout(60)
    d.set_script_timeout(60)
    proof={}
    try:
        r.start(d)
        r.base_views(d)
        r.building_gate(d)
        r.e2e(d)
        r.online_mock(d)
        mobile=mobile_gameplay_e2e(d)
        mobile_online=mobile_online_e2e(d)
        proof={
            'pass':True,
            'browser':'edge-public-eager-no-images',
            'tests':len(r.M),
            'manifest':r.M,
            'diagnostic':r.diagnostics(d),
            'mobile':mobile,
            'mobile_online':mobile_online,
            'visual_assets_tested_separately':True
        }
    except Exception as e:
        proof={
            'pass':False,
            'browser':'edge-public-eager-no-images',
            'error':repr(e),
            'tests':len(r.M),
            'manifest':r.M,
            'diagnostic':r.diagnostics(d),
            'visual_assets_tested_separately':True
        }
        raise
    finally:
        (r.OUT/'PROVA_BROWSER_RT79.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
    print(json.dumps({'pass':proof['pass'],'tests':proof['tests'],'browser':'edge','mobile':proof.get('mobile',{}).get('pass'),'mobile_online':proof.get('mobile_online',{}).get('pass')}))

if __name__=='__main__':
    main()
