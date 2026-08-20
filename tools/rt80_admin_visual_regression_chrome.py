from pathlib import Path
import json, os, time, re
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import TimeoutException
import rt80_admin_visual_regression as base

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_ADMIN_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[],'tabs':[],'phase':'init'}

def log(x): print('[RT80-ADM-CHROME]',x,flush=True)
def save_proof(): (OUT/'PROVA_RT80_ADMIN_VISUAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
def phase(name): proof['phase']=name;save_proof();log('PHASE '+name)
def check(d,name,js,timeout=6):
    WebDriverWait(d,timeout).until(lambda x:bool(x.execute_script(js)))
    proof['checks'].append({'name':name,'pass':True});save_proof();log('PASS '+name)
def shot(d,name):
    p=OUT/f'{len(proof["screenshots"])+1:02d}_{name}.png';d.save_screenshot(str(p));proof['screenshots'].append(p.name);save_proof();log('SHOT '+name)
def close_modals(d): d.execute_script("document.querySelectorAll('.rt64-modal,.rt60-admin-modal').forEach(x=>x.remove())")
def open_modal(d,selector,name):
    d.execute_script("document.querySelector(arguments[0])?.click()",selector)
    WebDriverWait(d,5).until(lambda x:x.execute_script("return !!document.querySelector('.rt64-modal,.rt60-admin-modal')"))
    check(d,name+' role',"return document.querySelector('.rt64-modal,.rt60-admin-modal')?.getAttribute('role')==='dialog'",5)
    shot(d,name);close_modals(d);time.sleep(.05)

def prepare():
    base.prepare_html()
    s=base.AUDIT_HTML.read_text(encoding='utf-8')
    s=re.sub(r'<script\b[^>]*\bsrc=["\'][^"\']+["\'][^>]*>\s*</script>','',s,flags=re.I)
    s=s.replace('bootstrapOnline();','/* RT80 ADMIN AUDIT: normal bootstrap intentionally disabled */',1)
    css=(base.ROOT/'rt80-admin-cleanup.css').read_text(encoding='utf-8')
    runtime=(base.ROOT/'rt80-admin-runtime.js').read_text(encoding='utf-8')
    s=s.replace('</head>',f'<style id="rt80-admin-audit-css">{css}</style>\n</head>',1)
    s=s.replace('</body>',f'<script id="rt80-admin-audit-runtime">{runtime}</script>\n</body>',1)
    base.AUDIT_HTML.write_text(s,encoding='utf-8')

def main():
    prepare();phase('audit_html_ready')
    opts=Options();opts.page_load_strategy='eager'
    opts.add_argument('--headless=new');opts.add_argument('--no-sandbox');opts.add_argument('--disable-gpu');opts.add_argument('--disable-dev-shm-usage');opts.add_argument('--window-size=1600,1000')
    opts.add_experimental_option('prefs',{'profile.managed_default_content_settings.images':2})
    opts.set_capability('goog:loggingPrefs',{'browser':'ALL'})
    d=None
    try:
        phase('creating_chrome_session')
        d=webdriver.Chrome(options=opts)
        phase('chrome_session_ready')
        d.set_page_load_timeout(30);d.set_script_timeout(15)
        try:d.get(BASE+'rt80_admin_audit.html?audit=1')
        except TimeoutException:log('page load timeout tolerated')
        phase('page_opened')
        WebDriverWait(d,20).until(lambda x:x.execute_script('return !!window.__RT80_ADMIN_AUDIT__'))
        phase('admin_api_ready')
        d.execute_script("""
          const data=arguments[0];
          const a=window.__RT80_ADMIN_AUDIT__;
          a.RTADMIN.token='audit-only';a.RTADMIN.username='auditoria';a.RTADMIN.info={username:'auditoria',role:'superadmin'};a.RTADMIN.ui={tab:'overview',worldId:'w1',mapX:500,mapY:500};
          window.__RT80_ADMIN_RENDER_RESULT__={started:true,settled:false,error:null};
          try {
            const p=a.renderIntegratedAdmin(data,true);
            Promise.resolve(p).then(()=>{window.__RT80_ADMIN_RENDER_RESULT__.settled=true;}).catch(e=>{
              window.__RT80_ADMIN_RENDER_RESULT__.settled=true;
              window.__RT80_ADMIN_RENDER_RESULT__.error=String(e?.stack||e);
            });
          } catch(e) {
            window.__RT80_ADMIN_RENDER_RESULT__.settled=true;
            window.__RT80_ADMIN_RENDER_RESULT__.error=String(e?.stack||e);
          }
          return true;
        """,base.MOCK)
        phase('admin_render_dispatched')
        WebDriverWait(d,20).until(lambda x:x.execute_script("return !!document.querySelector('.rt60-admin-shell') || !!window.__RT80_ADMIN_RENDER_RESULT__?.error"))
        render_error=d.execute_script("return window.__RT80_ADMIN_RENDER_RESULT__?.error || null")
        if render_error: raise RuntimeError(render_error)
        phase('admin_dom_ready')
        try:
            WebDriverWait(d,5).until(lambda x:x.execute_script("return window.__RT80_ADMIN_RENDER_RESULT__?.settled===true"))
        except TimeoutException:
            proof['rendererPromiseSettled']=False;save_proof();log('WARN renderer promise still pending after DOM became ready')
        else:
            proof['rendererPromiseSettled']=True;save_proof();log('PASS renderer promise settled')
        check(d,'admin shell',"return !!document.querySelector('.rt60-admin-shell')")
        check(d,'runtime ready',"return document.querySelector('.rt60-admin-shell')?.dataset.rt80AdminReady==='1'")
        check(d,'15 tabs',"return document.querySelectorAll('[data-admin-tab]').length===15")
        check(d,'branding RT80',"return !/\\bRT(?:[1-7]\\d)(?:\\.\\d+)?\\b/i.test(document.querySelector('.rt60-admin-top')?.innerText||'')")
        check(d,'table semantics',"return [...document.querySelectorAll('.rt60-admin-shell th')].every(x=>x.getAttribute('scope')==='col')")
        for tab,label in base.TABS:
            d.execute_script("document.querySelector('[data-admin-tab=\"'+arguments[0]+'\"]')?.click()",tab);time.sleep(.05)
            check(d,tab+' visible',f"const p=document.querySelector('[data-admin-panel=\\\"{tab}\\\"]');return !!p&&!p.classList.contains('hidden')",5)
            shot(d,'ADMIN_'+label);proof['tabs'].append(tab)
        d.execute_script("document.querySelector('[data-admin-tab=\"players\"]')?.click()");time.sleep(.05);open_modal(d,'[data-rt64-edit-player]','ADMIN_MODAL_PLAYER')
        d.execute_script("document.querySelector('[data-admin-tab=\"villages\"]')?.click()");time.sleep(.05);open_modal(d,'[data-rt64-edit-village]','ADMIN_MODAL_VILLAGE')
        d.execute_script("document.querySelector('[data-admin-tab=\"events\"]')?.click()");time.sleep(.05);open_modal(d,'[data-rt64-edit-event]','ADMIN_MODAL_EVENT');open_modal(d,'[data-rt64-edit-monster]','ADMIN_MODAL_MONSTER')
        d.set_window_size(430,932);time.sleep(.1);d.execute_script("document.querySelector('[data-admin-tab=\"overview\"]')?.click()");time.sleep(.05)
        check(d,'mobile nav',"const n=document.querySelector('.rt60-admin-nav');return !!n&&getComputedStyle(n).display==='flex'",5);shot(d,'ADMIN_MOBILE_OVERVIEW')
        proof['pass']=True;phase('complete')
    except Exception as e:
        proof['error']=repr(e);log('FAIL '+repr(e));save_proof()
        if d:
            try:shot(d,'ADMIN_FAILURE')
            except Exception:pass
        raise
    finally:
        if d:
            try: proof['console']=d.get_log('browser')
            except Exception: proof['console']=[]
            save_proof()
            try:d.quit()
            except Exception:pass
        try:base.AUDIT_HTML.unlink()
        except Exception:pass
    log('ALL PASS')
if __name__=='__main__':main()
