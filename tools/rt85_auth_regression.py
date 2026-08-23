import json, os, time
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT85_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT85_AUTH_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'backend':'turso','checks':[]}

def check(d,name,js,timeout=25):
    WebDriverWait(d,timeout).until(lambda x: bool(x.execute_script(js)))
    proof['checks'].append({'name':name,'pass':True})

def main():
    o=Options();o.page_load_strategy='eager';o.add_argument('--headless=new');o.add_argument('--disable-gpu');o.add_argument('--no-sandbox');o.add_argument('--window-size=1400,950')
    d=webdriver.Edge(options=o)
    try:
        d.get(BASE+'?rt-turso-auth=1')
        check(d,'Turso bridge loaded before app','return window.__RT_TURSO_BRIDGE__===true')
        check(d,'legacy Supabase blocked','return window.ReinoTribalTurso?.blockLegacySupabase===true')
        check(d,'landing','return !!document.querySelector("[data-entry-online]")')
        d.execute_script('document.querySelector("[data-entry-online]").click()')
        check(d,'login form visible','return !!document.querySelector("#rt18-login-form") && getComputedStyle(document.querySelector("#rt18-login-form")).display!=="none"')
        check(d,'identifier input','return !!document.querySelector("#rt18-login-form [name=email]")')
        check(d,'password input','return !!document.querySelector("#rt18-login-form [name=password]")')
        check(d,'Turso status note','return !!document.querySelector("[data-rt-turso-note]")')
        time.sleep(2)
        resources=d.execute_script('return performance.getEntriesByType("resource").map(x=>x.name)') or []
        leaked=[u for u in resources if 'rlyiwlwzrdgvcwawrnpl.supabase.co' in u]
        if leaked:
            raise AssertionError('Requisição real ao Supabase legado detectada: '+repr(leaked[:5]))
        proof['checks'].append({'name':'zero network requests to legacy Supabase','pass':True})
        proof['resources_checked']=len(resources)
        proof['api_base']=d.execute_script('return window.ReinoTribalTurso?.apiBase||""')
        d.save_screenshot(str(OUT/'RT_TURSO_LOGIN_UI.png'))
        proof['pass']=all(x['pass'] for x in proof['checks'])
    except Exception as e:
        proof['error']=repr(e)
        try:d.save_screenshot(str(OUT/'RT_TURSO_AUTH_FAILURE.png'))
        except Exception:pass
        raise
    finally:
        (OUT/'PROVA_RT_TURSO_AUTH.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
if __name__=='__main__': main()
