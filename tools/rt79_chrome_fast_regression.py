import os,time,json
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.common.exceptions import TimeoutException

URL=os.environ.get('RT79_TEST_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT79_BROWSER_REGRESSION';OUT.mkdir(parents=True,exist_ok=True)
M=[]
def rec(n,ok=True,d=''):
 M.append({'name':n,'pass':bool(ok),'detail':d})
 if not ok: raise AssertionError(f'{n}: {d}')
def js(d,s,*a): return d.execute_script(s,*a)
def click(d,sel):
 ok=js(d,"const e=document.querySelector(arguments[0]);if(!e)return false;e.click();return true",sel);rec('click '+sel,ok);time.sleep(.08)
def diagnostics(d):
 try:
  return {'title':d.title,'url':d.current_url,'readyState':js(d,'return document.readyState'),'scripts':js(d,"return [...document.scripts].map(s=>s.src||s.id||'inline').filter(x=>x.includes('rt79')||x.includes('rt76')||x.includes('rt78'))"),'hasPlay':js(d,"return !!document.querySelector('[data-play-offline]')"),'hasSuite':js(d,'return !!window.__RT79_STRATEGY_SUITE__'),'console':d.get_log('browser')[-30:]}
 except Exception as e:return {'diagnostic_error':repr(e)}
def nav(d,suffix=''):
 try:d.get(URL+suffix)
 except TimeoutException:pass
 WebDriverWait(d,25).until(lambda x: js(x,'return !!document.body'))
 WebDriverWait(d,25).until(lambda x: js(x,"return !!document.querySelector('[data-play-offline]')"))

def start(d):
 nav(d,'?fast=1')
 diag=diagnostics(d);(OUT/'BROWSER_DIAGNOSTIC_START.json').write_text(json.dumps(diag,ensure_ascii=False,indent=2),encoding='utf-8')
 WebDriverWait(d,25).until(lambda x: js(x,'return !!window.__RT79_STRATEGY_SUITE__'))
 js(d,"Object.keys(localStorage).filter(k=>k.startsWith('reinos_tribais_ptbr_save_')).forEach(k=>localStorage.removeItem(k))")
 rec('RT79 suite',js(d,'return !!window.__RT79_STRATEGY_SUITE__'))
 click(d,'[data-play-offline]');f=WebDriverWait(d,8).until(lambda x:x.find_element(By.CSS_SELECTOR,'#start-form'))
 js(d,"arguments[0].elements.playerName.value='Audit';arguments[0].elements.villageName.value='Aldeia';arguments[0].elements.difficulty.value='normal';arguments[0].elements.mapRadius.value='16';arguments[0].elements.startProfile.value='military';arguments[0].requestSubmit()",f)
 WebDriverWait(d,12).until(lambda x:js(x,'return !!window.RT76?.state?.()?.activeVillageId'));rec('game started',True)
 WebDriverWait(d,8).until(lambda x:js(x,"return !!document.querySelector('[data-rt79-open]')"));rec('launcher in game',True)

def base_views(d):
 for v in ['systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']:
  ok=js(d,"const e=document.querySelector('[data-view=\"'+arguments[0]+'\"]');if(!e)return false;e.click();return true",v);rec('view '+v,ok)

def building_gate(d):
 click(d,'[data-view="buildings"]');keys=js(d,"return [...new Set([...document.querySelectorAll('[data-open-building]')].map(x=>x.dataset.openBuilding).filter(Boolean))]");rec('19 buildings',len(keys)>=19,str(len(keys)))
 for k in keys[:19]:
  ok=js(d,"const e=[...document.querySelectorAll('[data-open-building]')].find(x=>x.dataset.openBuilding===arguments[0]);if(!e)return false;e.click();return true",k);rec('building '+k,ok);rec('detail '+k,js(d,"return !!document.querySelector('[data-building-detail=\"'+arguments[0]+'\"]')",k))

def e2e(d):
 js(d,"const s=RT76.state(),v=s.villages[s.activeVillageId];v.resources.wood=v.resources.clay=v.resources.iron=999999;v.buildQueue=[];v.recruitQueue=[];v.units.spear=500;for(const k of Object.keys(v.buildings||{})){const mx=Number(window.GAME_DATA?.buildings?.[k]?.max||30);v.buildings[k]=Math.min(mx,Math.max(Number(v.buildings[k]||0),['farm','warehouse'].includes(k)?30:10));}s.player.research=s.player.research||{queue:[],completed:[]};s.player.research.queue=[];if(v.unitResearch)v.unitResearch.spear=1;RT76.save()")
 click(d,'[data-view="buildings"]');before=js(d,"const s=RT76.state();return s.villages[s.activeVillageId].buildQueue.length");key=js(d,"const e=document.querySelector('[data-build]:not([disabled])');if(!e)return '';e.click();return e.dataset.build||''");after=js(d,"const s=RT76.state();return s.villages[s.activeVillageId].buildQueue.length");rec('build queue',bool(key) and after>before,key)
 click(d,'[data-view="recruit"]');before=js(d,"const s=RT76.state();return s.villages[s.activeVillageId].recruitQueue.length");key=js(d,"const e=document.querySelector('[data-recruit]:not([disabled])');if(!e)return '';const q=document.querySelector('#qty-'+e.dataset.recruit);if(q)q.value='1';e.click();return e.dataset.recruit||''");after=js(d,"const s=RT76.state();return s.villages[s.activeVillageId].recruitQueue.length");rec('recruit queue',bool(key) and after>before,key)
 click(d,'[data-view="research"]');before=js(d,"return (RT76.state().player?.research?.queue||[]).length");key=js(d,"const e=document.querySelector('[data-research]:not([disabled])');if(!e)return '';e.click();return e.dataset.research||''");after=js(d,"return (RT76.state().player?.research?.queue||[]).length");rec('research queue',bool(key) and after>before,key)
 js(d,"const s=RT76.state(),v=s.villages[s.activeVillageId];v.resources.wood=5000;v.resources.clay=1000;v.resources.iron=1000;v.buildings.warehouse=20")
 click(d,'[data-view="market"]');before=js(d,"const s=RT76.state(),v=s.villages[s.activeVillageId];return [v.resources.wood,v.resources.clay]");ok=js(d,"const f=document.querySelector('#market-form');if(!f)return false;f.elements.from.value='wood';f.elements.to.value='clay';f.elements.amount.value='100';f.requestSubmit();return true");after=js(d,"const s=RT76.state(),v=s.villages[s.activeVillageId];return [v.resources.wood,v.resources.clay]");rec('market exchange',ok and after[0]<before[0] and after[1]>before[1],str([before,after]))
 click(d,'[data-view="map"]');target=js(d,"const s=RT76.state(),t=Object.values(s.villages).find(v=>v.owner!=='player');if(!t)return null;s.ui.mapCenter={x:t.x,y:t.y};return t.id");rec('attack target',bool(target),str(target));click(d,'[data-view="map"]');rec('target rendered',js(d,"const e=[...document.querySelectorAll('[data-target]')].find(x=>x.dataset.target===arguments[0]);if(!e)return false;e.click();return true",target));before=js(d,'return RT76.state().commands.length');ok=js(d,"const f=document.querySelector('#attack-form');if(!f)return false;const i=f.querySelector('[name=\"attack_spear\"]');if(!i)return false;i.value='1';f.requestSubmit();return true");after=js(d,'return RT76.state().commands.length');rec('attack command',ok and after>before)
 js(d,"const s=RT76.state(),h=s.player.hero;h.story=h.story||{};h.story.inventory=h.story.inventory||[];if(!h.story.inventory.includes('dawnblade'))h.story.inventory.push('dawnblade');h.story.equipment=h.story.equipment||{};delete h.story.equipment.weapon");click(d,'[data-view="arsenal"]');ok=js(d,"const e=document.querySelector('[data-equip-hero-item=\"dawnblade\"]');if(!e)return false;e.click();return true");rec('paladin equip',ok and js(d,"return RT76.state().player.hero.story.equipment.weapon==='dawnblade'"))
 # IA: construção/recrutamento/ataque do núcleo + pesquisa RT79.1 paga por recursos.
 ai=js(d,"const s=RT76.state(),v=Object.values(s.villages).find(v=>v.owner==='ai');if(!v)return null;v.buildings.smith=Math.max(10,Number(v.buildings.smith||0));v.resources.wood=v.resources.clay=v.resources.iron=99999;v.unitResearch={};s.rt76.aiResearchNextAt=0;const before={r:{...v.resources},q:{...v.unitResearch},cmd:s.commands.length};const researched=RT79_AI_RESEARCH.tick();RT76.ai.process(Date.now()+999999);return {researched,before,after:{r:v.resources,q:v.unitResearch,cmd:s.commands.length},activity:RT76.ai.activity().slice(0,10)}")
 rec('AI village exists',bool(ai),str(ai));rec('AI research',bool(ai and ai['researched'] and ai['after']['q']),json.dumps(ai,ensure_ascii=False) if ai else '')
 rec('AI observable activity',bool(ai and ai['activity']),json.dumps(ai['activity'] if ai else [],ensure_ascii=False))
 name=js(d,"RT76.save();return RT76.state().player.name");nav(d,'?reload=1');WebDriverWait(d,20).until(lambda x:js(x,'return !!window.__RT79_STRATEGY_SUITE__'));click(d,'[data-play-offline]');rec('save reload',js(d,"return RT76.state()?.player?.name||''")==name)

def online_mock(d):
 mock={'version':79,'settings':{'farm':{'activeTemplate':'A','templates':{'A':{'spear':25},'B':{'axe':40},'C':{'light':40}}},'manager':{},'market':{},'scavenge':{},'villageMeta':{}},'villages':[{'id':'v1','name':'A','x':500,'y':500,'points':1000,'resources':{'wood':1000,'clay':1000,'iron':1000},'units':{'spear':100},'buildings':{'warehouse':10,'watchtower':1},'build_queue':[],'recruit_queue':[]}],'targets':[{'id':'b1','name':'B','x':501,'y':501,'points':200,'owner_kind':'barbarian','buildings':{'wall':1}}],'incoming_tactical':[],'outgoing':[],'scheduled':[],'routes':[],'intel':[],'logs':[],'upcoming_events':[],'scavenge_jobs':[],'resource_transfers':[],'barbarian_ai':[{'village_id':'b1','name':'B','x':501,'y':501,'points':200,'personality':'opportunist','threat_level':1,'wall':1,'next_tick':'2026-08-18T23:00:00Z'}]}
 js(d,"window.CLOUD=window.CLOUD||{};CLOUD.session={access_token:'audit'};CLOUD.worldId='w1';CLOUD.url='https://audit.invalid';CLOUD.key='audit';const mock=JSON.parse(arguments[0]);window.fetch=async(u,o)=>{const s=String(u);if(s.includes('/rest/v1/rpc/rt79_dashboard'))return new Response(JSON.stringify(mock),{status:200,headers:{'Content-Type':'application/json'}});if(s.includes('/rest/v1/rpc/'))return new Response(JSON.stringify({ok:true}),{status:200,headers:{'Content-Type':'application/json'}});return new Response('{}',{status:404})}",json.dumps(mock))
 js(d,'window.RT79.open()');WebDriverWait(d,8).until(lambda x:js(x,"return document.querySelector('#rt79-overlay')?.classList.contains('open')"))
 for t in ['overview','war','farm','market','manager','empire','intel','history']:
  rec('RT79 tab '+t,js(d,"const e=document.querySelector('[data-rt79-tab=\"'+arguments[0]+'\"]');if(!e)return false;e.click();return true",t))
 js(d,"document.querySelector('[data-rt79-close]')?.click();document.querySelector('[data-view=\"overview\"]')?.click()");time.sleep(.15)
 rec('village toolbar',js(d,"return !!document.querySelector('.rt79-village-toolbar')"));rec('village 19 hitboxes',js(d,"return document.querySelectorAll('.village-scene .rt60-village-hitbox').length>=19"));rec('raster map',js(d,"return !!document.querySelector('.village-scene>.rt54-map-layer')"));rec('real wall',js(d,"return !!document.querySelector('.village-scene [data-village-building=\"wall\"]')"));rec('no fake overlay',js(d,"return document.querySelectorAll('.rt79-road-net,.rt79-wall-perimeter').length===0"))
 js(d,'window.RT79.open()');time.sleep(.1);click(d,'[data-rt79-tab="market"]');WebDriverWait(d,7).until(lambda x:js(x,"return !!document.querySelector('#rt79-logistics-card')"));rec('logistics UI',True);click(d,'[data-rt79-tab="farm"]');WebDriverWait(d,7).until(lambda x:js(x,"return !!document.querySelector('#rt79-barb-ai-card')"));rec('barbarian AI UI',True);click(d,'[data-rt79-tab="manager"]');WebDriverWait(d,7).until(lambda x:js(x,"return !!document.querySelector('#rt79-group-goals-card')"));rec('group goals UI',True)

def main():
 opts=Options();opts.page_load_strategy='eager';opts.add_argument('--headless=new');opts.add_argument('--no-sandbox');opts.add_argument('--disable-gpu');opts.add_argument('--disable-dev-shm-usage');opts.add_argument('--window-size=1280,800');opts.add_experimental_option('prefs',{'profile.managed_default_content_settings.images':2});opts.set_capability('goog:loggingPrefs',{'browser':'ALL'})
 d=webdriver.Chrome(options=opts);d.set_page_load_timeout(30);d.set_script_timeout(15)
 proof={}
 try:
  start(d);base_views(d);building_gate(d);e2e(d);online_mock(d);d.set_window_size(390,844);rec('mobile suite',js(d,'return !!window.__RT79_STRATEGY_SUITE__'));proof={'pass':True,'browser':'chrome','tests':len(M),'manifest':M,'diagnostic':diagnostics(d)}
 except Exception as e:
  proof={'pass':False,'browser':'chrome','error':repr(e),'tests':len(M),'manifest':M,'diagnostic':diagnostics(d)};raise
 finally:
  (OUT/'PROVA_BROWSER_RT79.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8');d.quit()
 print(json.dumps({'pass':proof['pass'],'tests':proof['tests']}))
if __name__=='__main__':main()
