import os,time,json
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait
import rt79_browser_regression as r

URL=os.environ.get('RT79_TEST_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT79_BROWSER_REGRESSION'
OUT.mkdir(parents=True,exist_ok=True)

def req(d,js,msg,timeout=12):
    WebDriverWait(d,timeout).until(lambda x:x.execute_script(js))
    if not d.execute_script(js): raise AssertionError(msg)

def main():
    opts=Options();opts.add_argument('--headless=new');opts.add_argument('--disable-gpu');opts.add_argument('--no-sandbox');opts.add_argument('--window-size=1600,1000')
    d=webdriver.Edge(options=opts)
    proof={}
    try:
        d.get(URL+'?rt79-addon-smoke=1');WebDriverWait(d,25).until(lambda x:x.execute_script("return document.readyState==='complete'"));time.sleep(.7)
        flags=d.execute_script("return {suite:!!window.__RT79_STRATEGY_SUITE__,groups:!!window.__RT79_GROUPS_ADDON__,logistics:!!window.__RT79_LOGISTICS_AI_ADDON__,village:!!window.__RT79_VILLAGE_UI__}")
        if not all(flags.values()): raise AssertionError('RT79 addon loaders missing '+json.dumps(flags))
        d.execute_script("document.querySelector('[data-play-offline]')?.click()")
        f=WebDriverWait(d,8).until(lambda x:x.find_element(r.By.CSS_SELECTOR,'#start-form'))
        d.execute_script("arguments[0].elements.playerName.value='Auditoria Addons';arguments[0].elements.villageName.value='Aldeia Visual';arguments[0].elements.difficulty.value='normal';arguments[0].elements.mapRadius.value='16';arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit();",f);time.sleep(1)
        req(d,"return !!document.querySelector('.rt79-village-toolbar')",'village toolbar missing')
        hit=d.execute_script("return document.querySelectorAll('.village-scene .rt60-village-hitbox').length")
        if hit<19: raise AssertionError(f'expected 19 village hitboxes, got {hit}')
        req(d,"return !!document.querySelector('.rt79-wall-perimeter')",'wall perimeter missing')
        d.execute_script("document.querySelector('[data-rt79-vcat=\"military\"]')?.click()")
        focused=d.execute_script("return [document.querySelectorAll('.village-scene .rt79-focus').length,document.querySelectorAll('.village-scene .rt79-dim').length]")
        if focused[0]<1 or focused[1]<1: raise AssertionError('category filtering did not affect scene')
        d.save_screenshot(str(OUT/'ADDON_01_ALDEIA_2_0.png'))
        r.install_mock(d);d.execute_script("window.RT79.open()")
        req(d,"return document.querySelector('#rt79-overlay')?.classList.contains('open')",'RT79 overlay missing')
        d.execute_script("document.querySelector('[data-rt79-tab=\"market\"]')?.click()");time.sleep(.8)
        req(d,"return !!document.querySelector('#rt79-logistics-card')",'timed logistics UI missing')
        d.save_screenshot(str(OUT/'ADDON_02_LOGISTICA.png'))
        d.execute_script("document.querySelector('[data-rt79-tab=\"farm\"]')?.click()");time.sleep(.8)
        req(d,"return !!document.querySelector('#rt79-barb-ai-card')",'barbarian AI UI missing')
        d.save_screenshot(str(OUT/'ADDON_03_IA_BARBARA.png'))
        d.execute_script("document.querySelector('[data-rt79-tab=\"manager\"]')?.click()");time.sleep(.8)
        req(d,"return !!document.querySelector('#rt79-group-goals-card')",'group goals UI missing')
        d.save_screenshot(str(OUT/'ADDON_04_METAS_GRUPO.png'))
        proof={'pass':True,'loaders':flags,'village_hitboxes':hit,'focused':focused,'cards':['logistics','barbarian_ai','group_goals']}
    except Exception as e:
        proof={'pass':False,'error':repr(e)}
        try:d.save_screenshot(str(OUT/'ADDON_FAILURE.png'))
        except Exception:pass
        raise
    finally:
        (OUT/'PROVA_ADDONS_RT79.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8');d.quit()
if __name__=='__main__':main()
