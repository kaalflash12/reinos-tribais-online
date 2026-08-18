from pathlib import Path
import json,time
from selenium.common.exceptions import TimeoutException
import rt79_browser_regression as r

PUBLIC=r.PUBLIC

def safe_nav(d,url,timeout=40):
    d.set_page_load_timeout(timeout)
    try:
        d.get(url)
    except TimeoutException:
        try:d.execute_script('window.stop()')
        except Exception:pass
    r.WebDriverWait(d,30).until(lambda x:x.execute_script("return document.readyState==='interactive'||document.readyState==='complete'"))
    time.sleep(1.5)

def start_local(d):
    safe_nav(d,PUBLIC+'?rt79-browser-audit=2')
    r.require(d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'),'RT79 suite not loaded')
    r.require(d.execute_script("return !!document.querySelector('[data-rt79-open]')"),'RT79 launcher absent')
    r.shot(d,'00_entry_rt79_loaded')
    r.click(d,'[data-play-offline]')
    f=d.find_element(r.By.CSS_SELECTOR,'#start-form')
    d.execute_script("arguments[0].elements.playerName.value='Auditoria RT79';arguments[0].elements.villageName.value='Aldeia RT79';arguments[0].elements.difficulty.value='normal';arguments[0].elements.mapRadius.value='16';arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit();",f)
    time.sleep(2.5)
    r.shot(d,'01_overview_desktop')

def mobile(d):
    d.set_window_size(390,844)
    safe_nav(d,PUBLIC+'?rt79-browser-mobile=2')
    r.require(d.execute_script('return !!window.__RT79_STRATEGY_SUITE__'),'RT79 missing mobile')
    r.shot(d,'mobile_entry')
    if d.execute_script("return !!document.querySelector('[data-play-offline]')"):
        r.click(d,'[data-play-offline]');time.sleep(.5)
    r.shot(d,'mobile_game_or_start')
    if d.execute_script("return !!document.querySelector('[data-rt79-open]')"):
        r.install_mock(d);r.click(d,'[data-rt79-open]');time.sleep(.8);r.shot(d,'mobile_rt79')

r.start_local=start_local
r.mobile=mobile
r.main()
