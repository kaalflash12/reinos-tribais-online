from pathlib import Path
import json, os, time, re
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
import rt80_admin_visual_regression as base

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_ADMIN_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[],'tabs':[]}

def log(x): print('[RT80-ADM-CHROME]',x,flush=True)
def check(d,name,js,timeout=8):
    WebDriverWait(d,timeout).until(lambda x:bool(x.execute_script(js)))
    proof['checks'].append({'name':name,'pass':True});log('PASS '+name)
def shot(d,name):
    p=OUT/f'{len(proof["screenshots"])+1:02d}_{name}.png';d.save_screenshot(str(p));proof['screenshots'].append(p.name);log('SHOT '+name)
def close_modals(d): d.execute_script("document.querySelectorAll('.rt64-modal,.rt60-admin-modal').forEach(x=>x.remove())")
def open_modal(d,selector,name):
    d.execute_script("document.querySelector(arguments[0])?.click()",selector)
    WebDriverWait(d,6).until(lambda x:x.execute_script("return !!document.querySelector('.rt64-modal,.rt60-admin-modal')"))
    check(d,name+' role',"return document.querySelector('.rt64-modal,.rt60-admin-modal')?.getAttribute('role')==='dialog'",6)
    shot(d,name);close_modals(d);time.sleep(.08)

def prepare():
    base.prepare_html()
    s=base.AUDIT_HTML.read_text(encoding='utf-8')
    s=re.sub(r'<script[^>]+src=["\']https://cdn\.jsdelivr\.net/[^"\']+["\'][^>]*>\s*</script>','',s,flags=re.I)
    # Do not let normal landing/bootstrap race the isolated renderer.
    s=s.replace('bootstrapOnline();','/* RT80 ADMIN AUDIT: normal bootstrap intentionally disabled */',1)
    base.AUDIT_HTML.write_text(s,encoding='utf-8')

def main():
    prepare();log('temporary audit HTML ready')
    o=Options();o.page_load_strategy='eager'
    for a in ['--headless=new','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--window-size=1600,1000','--disable-background-networking','--no-first-run']:
        o.add_argument(a)
    d=webdriver.Chrome(options=o);d.set_page_load_timeout(20);d.set_script_timeout(15)
    try:
        d.get(BASE+'rt80_admin_audit.html?audit=1')
        WebDriverWait(d,15).until(lambda x:x.execute_script('return !!window.__RT80_ADMIN_AUDIT__'))
        r=d.execute_async_script("""
          const data=arguments[0],done=arguments[arguments.length-1];
          const a=window.__RT80_ADMIN_AUDIT__;
          a.RTADMIN.token='audit-only';a.RTADMIN.username='auditoria';a.RTADMIN.info={username:'auditoria',role:'superadmin'};a.RTADMIN.ui={tab:'overview',worldId:'w1',mapX:500,mapY:500};
          a.renderIntegratedAdmin(data,true).then(()=>done({ok:true})).catch(e=>done({ok:false,error:String(e?.stack||e)}));
        """,base.MOCK)
        if not r.get('ok'): raise RuntimeError(r.get('error'))
        check(d,'admin shell',"return !!document.querySelector('.rt60-admin-shell')")
        check(d,'runtime ready',"return document.querySelector('.rt60-admin-shell')?.dataset.rt80AdminReady==='1'")
        check(d,'15 tabs',"return document.querySelectorAll('[data-admin-tab]').length===15")
        check(d,'branding RT80',"return !/\\bRT(?:[1-7]\\d)(?:\\.\\d+)?\\b/i.test(document.querySelector('.rt60-admin-top')?.innerText||'')")
        for tab,label in base.TABS:
            d.execute_script("document.querySelector('[data-admin-tab=\"'+arguments[0]+'\"]')?.click()",tab);time.sleep(.08)
            check(d,tab+' visible',f"const p=document.querySelector('[data-admin-panel=\\\"{tab}\\\"]');return !!p&&!p.classList.contains('hidden')",6)
            shot(d,'ADMIN_'+label);proof['tabs'].append(tab)
        d.execute_script("document.querySelector('[data-admin-tab=\"players\"]')?.click()");time.sleep(.08);open_modal(d,'[data-rt64-edit-player]','ADMIN_MODAL_PLAYER')
        d.execute_script("document.querySelector('[data-admin-tab=\"villages\"]')?.click()");time.sleep(.08);open_modal(d,'[data-rt64-edit-village]','ADMIN_MODAL_VILLAGE')
        d.execute_script("document.querySelector('[data-admin-tab=\"events\"]')?.click()");time.sleep(.08);open_modal(d,'[data-rt64-edit-event]','ADMIN_MODAL_EVENT');open_modal(d,'[data-rt64-edit-monster]','ADMIN_MODAL_MONSTER')
        d.set_window_size(430,932);time.sleep(.15);d.execute_script("document.querySelector('[data-admin-tab=\"overview\"]')?.click()");time.sleep(.08)
        check(d,'mobile nav',"const n=document.querySelector('.rt60-admin-nav');return !!n&&getComputedStyle(n).display==='flex'",6);shot(d,'ADMIN_MOBILE_OVERVIEW')
        proof['pass']=True
    except Exception as e:
        proof['error']=repr(e);log('FAIL '+repr(e))
        try:shot(d,'ADMIN_FAILURE')
        except Exception:pass
        raise
    finally:
        try: proof['console']=d.get_log('browser')
        except Exception: proof['console']=[]
        (OUT/'PROVA_RT80_ADMIN_VISUAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
        try:base.AUDIT_HTML.unlink()
        except Exception:pass
    log('ALL PASS')
if __name__=='__main__':main()
