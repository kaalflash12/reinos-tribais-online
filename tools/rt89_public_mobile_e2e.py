import json, os, time, uuid
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT89_URL','https://kaalflash12.github.io/reinos-tribais-online/')
API=os.environ.get('RT89_API','https://reino-tribal-api.mestrederpg35.deno.net')
WORLD='d5a546fb-316d-4332-ae92-1886d80b07df'
SESSION_KEY='reinos_tribais_supabase_session_v60_browser'
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT89_PUBLIC_MOBILE_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'browser':'edge-mobile-390x844','public_url':BASE,'api':API,'checks':[]}

def wait(d,name,js,timeout=45):
    WebDriverWait(d,timeout).until(lambda x: bool(x.execute_script(js)))
    proof['checks'].append({'name':name,'pass':True})

def api(d,action,payload=None,token=''):
    payload=payload or {}
    result=d.execute_async_script("""
      const base=arguments[0], action=arguments[1], payload=arguments[2], token=arguments[3], done=arguments[4];
      const headers={'Content-Type':'application/json'}; if(token)headers.Authorization='Bearer '+token;
      fetch(base+'/api/reino',{method:'POST',headers,body:JSON.stringify({action,...payload}),cache:'no-store'})
        .then(async r=>{const text=await r.text();let data=null;try{data=text?JSON.parse(text):null}catch{data={error:text}};done({ok:r.ok,status:r.status,data});})
        .catch(e=>done({ok:false,status:0,error:String(e)}));
    """,API,action,payload,token)
    if not result or not result.get('ok'):
        raise AssertionError(f'API {action} falhou: {result!r}')
    return result.get('data')

def main():
    suffix=uuid.uuid4().hex[:16]
    email=f'rt89-mobile-{suffix}@example.invalid'
    username=f'mob_{suffix}'
    password='Mob!'+uuid.uuid4().hex+'x'
    marker='mobile-'+uuid.uuid4().hex

    o=Options();o.page_load_strategy='eager';o.add_argument('--headless=new');o.add_argument('--disable-gpu');o.add_argument('--no-sandbox');o.add_argument('--disable-dev-shm-usage');o.add_argument('--window-size=390,844')
    d=webdriver.Edge(options=o);d.set_window_size(390,844);d.set_script_timeout(45);d.set_page_load_timeout(60)
    try:
        d.get(BASE+'?rt89-mobile='+str(int(time.time())))
        wait(d,'public Turso bridge','return window.__RT_TURSO_BRIDGE__===true && window.__RT89_RECOVERY_SAFE__===true')
        wait(d,'production API configured',f'return window.ReinoTribalTurso?.apiBase==={json.dumps(API)}')
        wait(d,'online entry visible','const e=document.querySelector("[data-entry-online]");return !!e && e.getBoundingClientRect().width>0')
        d.execute_script('document.querySelector("[data-entry-online]").click()')
        wait(d,'mobile login form visible','const f=document.querySelector("#rt18-login-form");return !!f && f.getBoundingClientRect().width>0 && f.getBoundingClientRect().width<=window.innerWidth')
        wait(d,'safe recovery UI on public page','const b=document.querySelector("[data-forgot-password]");const p=document.querySelector("[data-recovery-code-panel]");return !!b && b.textContent.includes("administrador") && (!p||p.hidden||getComputedStyle(p).display==="none")')
        d.save_screenshot(str(OUT/'01_PUBLIC_MOBILE_LOGIN.png'))

        reg=api(d,'register',{'email':email,'username':username,'password':password})
        if reg.get('user',{}).get('role')!='player' or not reg.get('access_token'):
            raise AssertionError('Registro mobile preparatório não retornou player/token')
        proof['checks'].append({'name':'production register from public mobile browser','pass':True})
        api(d,'logout',{},reg['access_token'])

        d.execute_script("""
          const f=document.querySelector('#rt18-login-form');
          f.querySelector('[name=email]').value=arguments[0];
          f.querySelector('[name=password]').value=arguments[1];
          f.querySelector('button[type=submit]').click();
        """,username,password)
        wait(d,'UI login created real player session',f"try{{const s=JSON.parse(sessionStorage.getItem({json.dumps(SESSION_KEY)})||'null');return !!s?.access_token && s?.user?.role==='player';}}catch(e){{return false;}}",60)
        sess=d.execute_script(f"return JSON.parse(sessionStorage.getItem({json.dumps(SESSION_KEY)})||'null')")
        token=sess['access_token']
        proof['checks'].append({'name':'mobile UI login via Turso bridge','pass':True})

        worlds=api(d,'list_worlds',{},token)
        if not any(str(w.get('id'))==WORLD for w in worlds):
            raise AssertionError('Mundo 1 ausente no navegador móvel')
        proof['checks'].append({'name':'Mundo 1 listed','pass':True})
        joined=api(d,'join_world',{'world_id':WORLD,'player_name':username},token)
        if not joined.get('ok') or str(joined.get('world',{}).get('id'))!=WORLD:
            raise AssertionError('join_world mobile não confirmou Mundo 1')
        proof['checks'].append({'name':'Mundo 1 joined','pass':True})

        state={'e2e_marker':marker,'player':username,'probe':'public-mobile-390x844','saved_at':time.time()}
        saved=api(d,'save',{'world_id':WORLD,'state':state},token)
        if not saved.get('ok') or int(saved.get('state_version',0))<1:
            raise AssertionError('save mobile não confirmou persistência')
        proof['checks'].append({'name':'mobile production save','pass':True})
        loaded=api(d,'load_save',{'world_id':WORLD},token)
        if not loaded or loaded.get('state',{}).get('e2e_marker')!=marker:
            raise AssertionError('load mobile não devolveu marcador exato')
        proof['checks'].append({'name':'mobile Turso load persistence','pass':True})

        membership=api(d,'player_world_get',{'world_id':WORLD},token)
        if str(membership.get('world_id'))!=WORLD:
            raise AssertionError('membership mobile não confirmado')
        proof['checks'].append({'name':'mobile membership','pass':True})

        overflow=d.execute_script('return Math.max(document.documentElement.scrollWidth,document.body.scrollWidth)-window.innerWidth')
        proof['page_horizontal_overflow_px']=overflow
        if overflow>4:
            raise AssertionError(f'Página móvel tem overflow horizontal global de {overflow}px')
        proof['checks'].append({'name':'no global horizontal overflow at 390px','pass':True})

        resources=d.execute_script('return performance.getEntriesByType("resource").map(x=>x.name)') or []
        leaked=[u for u in resources if 'rlyiwlwzrdgvcwawrnpl.supabase.co' in u]
        if leaked:
            raise AssertionError('Rede móvel vazou para Supabase legado: '+repr(leaked[:5]))
        proof['checks'].append({'name':'zero real Supabase network on mobile','pass':True})
        proof['resources_checked']=len(resources)
        d.save_screenshot(str(OUT/'02_PUBLIC_MOBILE_AUTHENTICATED.png'))
        api(d,'logout',{},token)
        proof['checks'].append({'name':'mobile logout','pass':True})
        proof['pass']=all(x['pass'] for x in proof['checks'])
    except Exception as e:
        proof['error']=repr(e)
        try:d.save_screenshot(str(OUT/'99_PUBLIC_MOBILE_FAILURE.png'))
        except Exception:pass
        raise
    finally:
        (OUT/'PROVA_RT89_PUBLIC_MOBILE.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()

if __name__=='__main__': main()
