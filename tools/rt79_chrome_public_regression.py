import json
from selenium import webdriver
import rt79_chrome_fast_regression as r

def main():
    opts=r.Options()
    opts.page_load_strategy='none'
    opts.add_argument('--headless=new')
    opts.add_argument('--no-sandbox')
    opts.add_argument('--disable-gpu')
    opts.add_argument('--disable-dev-shm-usage')
    opts.add_argument('--window-size=1280,800')
    opts.add_experimental_option('prefs',{'profile.managed_default_content_settings.images':2})
    opts.set_capability('goog:loggingPrefs',{'browser':'ALL'})
    d=webdriver.Chrome(options=opts)
    d.set_page_load_timeout(6)
    d.set_script_timeout(15)
    proof={}
    try:
        r.start(d)
        r.base_views(d)
        r.building_gate(d)
        r.e2e(d)
        r.online_mock(d)
        d.set_window_size(390,844)
        r.rec('mobile suite',r.js(d,'return !!window.__RT79_STRATEGY_SUITE__'))
        proof={'pass':True,'browser':'chrome-public-none','tests':len(r.M),'manifest':r.M,'diagnostic':r.diagnostics(d)}
    except Exception as e:
        proof={'pass':False,'browser':'chrome-public-none','error':repr(e),'tests':len(r.M),'manifest':r.M,'diagnostic':r.diagnostics(d)}
        raise
    finally:
        (r.OUT/'PROVA_BROWSER_RT79.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
    print(json.dumps({'pass':proof['pass'],'tests':proof['tests']}))

if __name__=='__main__':
    main()
