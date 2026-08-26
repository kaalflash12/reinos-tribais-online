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
        check(d,'final bridge version','return window.ReinoTribalTurso?.version==="1.0.6-turso-recovery-complete"')
        check(d,'legacy Supabase blocked','return window.ReinoTribalTurso?.blockLegacySupabase===true')
        check(d,'recovery safety marker','return window.__RT89_RECOVERY_SAFE__===true && window.ReinoTribalTurso?.recoveryMode==="admin-reset"')
        check(d,'landing','return !!document.querySelector("[data-entry-online]")')
        check(d,'landing backend label migrated','const x=document.querySelector(".rt55-status .rt55-live");return !!x && x.textContent.includes("Turso") && !/Supabase/i.test(x.textContent)')
        check(d,'landing copy migrated','const x=document.querySelector(".rt55-entry-copy > p");return !x || !/Supabase/i.test(x.textContent)')
        d.execute_script('document.querySelector("[data-entry-online]").click()')
        check(d,'login form visible','return !!document.querySelector("#rt18-login-form") && getComputedStyle(document.querySelector("#rt18-login-form")).display!=="none"')
        check(d,'identifier input','return !!document.querySelector("#rt18-login-form [name=email]")')
        check(d,'password input','return !!document.querySelector("#rt18-login-form [name=password]")')
        check(d,'Turso status note','return !!document.querySelector("[data-rt-turso-note]")')
        check(d,'login badge migrated','const x=document.querySelector(".rt18-online-badge");return !x || (!/Supabase/i.test(x.textContent) && x.textContent.includes("Turso"))')
        check(d,'legacy recovery code panel disabled','const p=document.querySelector("[data-recovery-code-panel]"); return !p || p.hidden || getComputedStyle(p).display==="none"')
        check(d,'recovery button converted','const b=document.querySelector("[data-forgot-password]"); return !!b && b.textContent.includes("administrador") && b.dataset.rtTursoRecoveryGuard==="1"')

        d.execute_script("const b=document.createElement('button');b.id='rt85-rt64-probe';b.setAttribute('data-rt64-recovery','probe-user');b.textContent='Recuperar';document.body.appendChild(b)")
        check(d,'RT64 admin recovery converted to Turso password reset','const b=document.querySelector("#rt85-rt64-probe");return !!b && b.getAttribute("data-admin-set-password")==="probe-user" && !b.hasAttribute("data-rt64-recovery") && b.textContent==="Definir nova senha"')
        d.execute_script("document.querySelector('#rt85-rt64-probe')?.remove()")

        before=d.execute_script('return performance.getEntriesByType("resource").map(x=>x.name)') or []
        d.execute_script('document.querySelector("#rt18-login-form [name=email]").value="recovery-test@example.invalid";document.querySelector("[data-forgot-password]").click()')
        check(d,'safe recovery notice','const m=document.querySelector("#rt18-auth-message"); return !!m && m.textContent.includes("administrador") && m.textContent.includes("Turso")')
        time.sleep(1)
        after=d.execute_script('return performance.getEntriesByType("resource").map(x=>x.name)') or []
        leaked=[u for u in after if 'rlyiwlwzrdgvcwawrnpl.supabase.co' in u]
        if leaked:
            raise AssertionError('Requisição real ao Supabase legado detectada: '+repr(leaked[:5]))
        if len(after)<len(before):
            raise AssertionError('Resource timing regressivo inesperado')
        proof['checks'].append({'name':'zero network requests to legacy Supabase','pass':True})
        proof['resources_checked']=len(after)
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
