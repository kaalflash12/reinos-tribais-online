import json,time,traceback
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.common.by import By

URL='https://kaalflash12.github.io/reinos-tribais-online/index.html?startup-bisect=1'
OUT=Path(__import__('os').environ.get('RUNNER_TEMP','/tmp'))/'RT79_STARTUP_BISECT'
OUT.mkdir(parents=True,exist_ok=True)

VARIANTS=[
 ('javascript_off',[],True),
 ('block_all_custom_js',['*rt76-*.js*','*rt78-*.js*','*rt79-*.js*','*rt73-village-runtime.js*'],False),
 ('block_all_rt79',['*rt79-*.js*'],False),
 ('block_rt79_suite',['*rt79-suite.js*'],False),
 ('block_rt79_village',['*rt79-village-ui.js*'],False),
 ('block_rt79_groups_logistics',['*rt79-groups-addon.js*','*rt79-logistics-ai-addon.js*'],False),
 ('block_rt79_admin',['*rt79-admin-suite.js*','*rt79-admin-logistics-addon.js*'],False),
 ('block_rt76_runtime',['*rt76-runtime.js*'],False),
 ('block_rt76_map_ai',['*rt76-map-ai.js*'],False),
 ('block_rt76_master_plan',['*rt76-master-plan.js*'],False),
 ('no_blocks',[],False),
]

def run_variant(name,blocked,js_off):
    opt=Options();opt.page_load_strategy='none'
    for arg in ['--headless=new','--disable-gpu','--no-first-run','--disable-dev-shm-usage','--ignore-certificate-errors','--window-size=1280,800']:
        opt.add_argument(arg)
    prefs={'profile.managed_default_content_settings.images':2}
    if js_off:prefs['profile.managed_default_content_settings.javascript']=2
    opt.add_experimental_option('prefs',prefs)
    d=None;result={'name':name,'blocked':blocked,'javascript_off':js_off,'pass':False}
    try:
        d=webdriver.Edge(options=opt)
        d.set_page_load_timeout(8);d.set_script_timeout(8)
        try:d.command_executor._client_config.timeout=12
        except Exception:pass
        d.execute_cdp_cmd('Network.enable',{})
        if blocked:d.execute_cdp_cmd('Network.setBlockedURLs',{'urls':blocked})
        t=time.time()
        try:d.get(URL+'&v='+name)
        except Exception as e:result['get_error']=repr(e)
        result['get_seconds']=round(time.time()-t,2)
        time.sleep(2)
        try:
            result['title']=d.title
            result['body_count']=len(d.find_elements(By.TAG_NAME,'body'))
            result['ready_state']=d.execute_script('return document.readyState')
            result['has_play']=d.execute_script("return !!document.querySelector('[data-play-offline]')")
            result['has_rt79']=d.execute_script('return !!window.__RT79_STRATEGY_SUITE__')
            result['pass']=result['body_count']==1 and result['ready_state'] in ('interactive','complete')
        except Exception as e:
            result['probe_error']=repr(e)
    except Exception as e:
        result['driver_error']=repr(e);result['traceback']=traceback.format_exc()[-2000:]
    finally:
        try:d.quit()
        except Exception:pass
    print(json.dumps(result,ensure_ascii=False),flush=True)
    return result

results=[run_variant(*v) for v in VARIANTS]
(OUT/'STARTUP_BISECT_RT79.json').write_text(json.dumps({'url':URL,'results':results},ensure_ascii=False,indent=2),encoding='utf-8')
working=[r['name'] for r in results if r.get('pass')]
print('WORKING_VARIANTS='+','.join(working))
if not working:raise SystemExit('Nenhuma variante carregou; travamento está no HTML/inline core ou ambiente.')
