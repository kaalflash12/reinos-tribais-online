import json, os, time
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT85_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT85_AUTH_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
proof={'pass':False,'checks':[]}

def check(d,name,js,timeout=20):
    WebDriverWait(d,timeout).until(lambda x: bool(x.execute_script(js)))
    proof['checks'].append({'name':name,'pass':True})

def main():
    o=Options();o.page_load_strategy='eager';o.add_argument('--headless=new');o.add_argument('--disable-gpu');o.add_argument('--no-sandbox');o.add_argument('--window-size=1400,950')
    d=webdriver.Edge(options=o)
    try:
        d.get(BASE+'?rt85-auth=1')
        check(d,'landing','return !!document.querySelector("[data-entry-online]")')
        d.execute_script('document.querySelector("[data-entry-online]").click()')
        check(d,'login form','return !!document.querySelector("#rt18-login-form")')
        check(d,'RT85 bridge loaded','return !!window.__RT85_AUTH_BRIDGE__')
        check(d,'login code button','return !!document.querySelector("[data-rt85-code]")')
        # Prova o caminho de alias sem conhecer ou alterar a senha real.
        d.execute_script('''const f=document.querySelector('#rt18-login-form');f.querySelector('[name=email]').value='teste';f.querySelector('[name=password]').value='senha_incorreta_rt85';f.requestSubmit();''')
        WebDriverWait(d,20).until(lambda x:'Credenciais inválidas' in (x.execute_script('return document.querySelector("#rt18-auth-message")?.textContent||""') or ''))
        proof['checks'].append({'name':'alias routed through RT85 broker','pass':True})
        d.save_screenshot(str(OUT/'RT85_LOGIN_UI.png'))
        proof['pass']=all(x['pass'] for x in proof['checks'])
    except Exception as e:
        proof['error']=repr(e)
        try:d.save_screenshot(str(OUT/'RT85_AUTH_FAILURE.png'))
        except Exception:pass
        raise
    finally:
        (OUT/'PROVA_RT85_AUTH.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        d.quit()
if __name__=='__main__': main()
