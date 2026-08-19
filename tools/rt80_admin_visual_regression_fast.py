from pathlib import Path
import json, os, time, sys
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait
import rt80_admin_visual_regression as base

BASE=os.environ.get('RT80_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT80_ADMIN_VISUAL_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'screenshots':[],'checks':[],'tabs':[]}


def log(msg):
    print('[RT80-ADM]',msg,flush=True)


def check(d,name,js,timeout=12):
    WebDriverWait(d,timeout).until(lambda x: bool(x.execute_script(js)))
    proof['checks'].append({'name':name,'pass':True}); log('PASS '+name)


def shot(d,name):
    p=OUT/f'{len(proof["screenshots"])+1:02d}_{name}.png';d.save_screenshot(str(p));proof['screenshots'].append(p.name)


def close_modals(d):
    d.execute_script("document.querySelectorAll('.rt64-modal,.rt60-admin-modal').forEach(x=>x.remove())");time.sleep(.12)


def open_modal(d,selector,name):
    d.execute_script("document.querySelector(arguments[0])?.click()",selector)
    WebDriverWait(d,8).until(lambda x:x.execute_script("return !!document.querySelector('.rt64-modal,.rt60-admin-modal')"))
    check(d,name+' runtime mark',"return !!document.querySelector('[data-rt80-admin-modal=\"1\"]')",8)
    check(d,name+' dialog role',"return document.querySelector('.rt64-modal,.rt60-admin-modal')?.getAttribute('role')==='dialog'",8)
    shot(d,name);close_modals(d)


def main():
    base.prepare_html(); log('audit HTML prepared')
    opts=Options();opts.page_load_strategy='none'
    for a in ['--headless=new','--disable-gpu','--no-sandbox','--window-size=1600,1000','--disable-dev-shm-usage','--disable-background-networking','--disable-default-apps','--no-first-run']:
        opts.add_argument(a)
    d=webdriver.Edge(options=opts);d.set_page_load_timeout(12);d.set_script_timeout(25)
    try:
        log('opening local audit page');d.get(BASE+'rt80_admin_audit.html?rt80-admin-audit=1')
        WebDriverWait(d,20).until(lambda x:x.execute_script("return !!window.__RT80_ADMIN_AUDIT__"));d.execute_script('window.stop()');log('renderer exposed; external loading stopped')
        result=d.execute_async_script("""
          const mock=arguments[0],done=arguments[arguments.length-1];
          (async()=>{try{const a=window.__RT80_ADMIN_AUDIT__;a.RTADMIN.token='audit-only';a.RTADMIN.username='auditoria';a.RTADMIN.info={username:'auditoria',role:'superadmin'};a.RTADMIN.ui={tab:'overview',worldId:'w1',mapX:500,mapY:500};await a.renderIntegratedAdmin(mock,true);done({ok:true})}catch(e){done({ok:false,error:String(e?.stack||e)})}})();
        """,base.MOCK)
        if not result.get('ok'): raise RuntimeError(result.get('error'))
        log('real admin renderer completed')
        check(d,'admin shell rendered',"return !!document.querySelector('.rt60-admin-shell')")
        check(d,'RT80 admin runtime ready',"return document.querySelector('.rt60-admin-shell')?.dataset.rt80AdminReady==='1'")
        check(d,'15 admin tabs exist',"return document.querySelectorAll('[data-admin-tab]').length===15")
        check(d,'header has no RT10-RT79 branding',"return !/\\bRT(?:[1-7]\\d)(?:\\.\\d+)?\\b/i.test(document.querySelector('.rt60-admin-top')?.innerText||'')")
        check(d,'table header semantics',"return [...document.querySelectorAll('.rt60-admin-shell th')].every(x=>x.getAttribute('scope')==='col')")
        for tab,label in base.TABS:
            log('tab '+tab)
            d.execute_script("document.querySelector('[data-admin-tab=\"'+arguments[0]+'\"]')?.click()",tab);time.sleep(.12)
            js=f"const p=document.querySelector('[data-admin-panel=\\\"{tab}\\\"]');return !!p&&getComputedStyle(p).display!=='none'"
            check(d,tab+' visible',js,8);check(d,tab+' no body overflow',"return document.documentElement.scrollWidth<=window.innerWidth+16",8);proof['tabs'].append(tab);shot(d,'ADMIN_'+label)
        d.execute_script("document.querySelector('[data-admin-tab=\"players\"]')?.click()");time.sleep(.15);open_modal(d,'[data-rt64-edit-player]','ADMIN_MODAL_PLAYER')
        d.execute_script("document.querySelector('[data-admin-tab=\"villages\"]')?.click()");time.sleep(.15);open_modal(d,'[data-rt64-edit-village]','ADMIN_MODAL_VILLAGE')
        d.execute_script("document.querySelector('[data-admin-tab=\"events\"]')?.click()");time.sleep(.15);open_modal(d,'[data-rt64-edit-event]','ADMIN_MODAL_EVENT');open_modal(d,'[data-rt64-edit-monster]','ADMIN_MODAL_MONSTER')
        d.set_window_size(430,932);time.sleep(.3);d.execute_script("document.querySelector('[data-admin-tab=\"overview\"]')?.click()");time.sleep(.2)
        check(d,'mobile no body overflow',"return document.documentElement.scrollWidth<=window.innerWidth+8",8)
        check(d,'mobile horizontal admin nav',"const n=document.querySelector('.rt60-admin-nav');return !!n&&getComputedStyle(n).display==='flex'&&n.getBoundingClientRect().height>35",8);shot(d,'ADMIN_MOBILE_OVERVIEW')
        proof['pass']=True;log('ALL ADMIN VISUAL CHECKS PASS')
    except Exception as e:
        proof['error']=repr(e);log('FAIL '+repr(e))
        try:shot(d,'ADMIN_FAILURE')
        except Exception:pass
        raise
    finally:
        try:proof['console']=d.get_log('browser')
        except Exception:proof['console']=[]
        (OUT/'PROVA_RT80_ADMIN_VISUAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
        try:base.AUDIT_HTML.unlink()
        except Exception:pass

if __name__=='__main__':main()
