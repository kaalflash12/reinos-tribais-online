from pathlib import Path
import os,json,time,subprocess,urllib.request,traceback
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait
PUBLIC='https://kaalflash12.github.io/reinos-tribais-online/'
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT77_PRINTS_FAST';OUT.mkdir(parents=True,exist_ok=True)
M=[]
def snap(d,k,n,note=''):
 f=OUT/f'{len(M)+1:03d}_{k}_{n}.png';d.save_screenshot(str(f));M.append({'kind':k,'name':n,'file':f.name,'notes':note});return f
def click(d,s):
 ok=d.execute_script("let e=document.querySelector(arguments[0]);if(e){e.click();return 1}return 0",s)
 if not ok:raise Exception('não encontrado '+s)
 time.sleep(.25)
def ready(d):WebDriverWait(d,20).until(lambda x:x.execute_script('return document.readyState')=='complete');time.sleep(.5)
def game(d):
 d.get(PUBLIC+'?prints=fast');ready(d);snap(d,'JOGO','entrada')
 click(d,'[data-play-offline]');snap(d,'JOGO','novo_reino')
 d.execute_script("let f=document.querySelector('#start-form');f.elements.playerName.value='Auditoria RT77';f.elements.villageName.value='Aldeia Teste';f.elements.mapRadius.value='16';f.elements.startProfile.value='military';f.requestSubmit()")
 time.sleep(2);snap(d,'JOGO','visao_geral')
 views=['systems','buildings','recruit','research','rally','academy','hero','arsenal','map','commands','missions','reports','messages','market','inventory','premium','manager','flags','ranking','tribe','help','settings','events','ranked']
 for v in views:
  try:click(d,f'[data-view="{v}"]');snap(d,'JOGO','pagina_'+v)
  except Exception as e:M.append({'kind':'ERRO','name':'pagina_'+v,'file':'','notes':str(e)})
 try:click(d,'[data-view="overview"]')
 except:pass
 keys=d.execute_script("return [...new Set([...document.querySelectorAll('[data-open-building]')].map(e=>e.dataset.openBuilding).filter(Boolean))]") or []
 if len(keys)<19:
  try:click(d,'[data-view="buildings"]')
  except:pass
  keys=list(dict.fromkeys(keys+(d.execute_script("return [...new Set([...document.querySelectorAll('[data-open-building]')].map(e=>e.dataset.openBuilding).filter(Boolean))]") or [])))
 for k in keys:
  try:click(d,f'[data-open-building="{k}"]');snap(d,'EDIFICIO',k);click(d,'[data-view="buildings"]')
  except Exception as e:M.append({'kind':'ERRO','name':'edificio_'+k,'file':'','notes':str(e)})
 d.get(PUBLIC+'?authprints=1');ready(d);click(d,'[data-entry-online]');snap(d,'CONTA','login_cadastro')
 try:click(d,'[data-forgot-password]');snap(d,'CONTA','recuperacao_codigo')
 except Exception as e:M.append({'kind':'ERRO','name':'recuperacao','file':'','notes':str(e)})
def mock():
 w='11111111-1111-4111-8111-111111111111';u='22222222-2222-4222-8222-222222222222';v='33333333-3333-4333-8333-333333333333';now='2026-08-17T20:50:00Z'
 return {'version':77,'generated_at':now,
 'worlds':[{'id':w,'name':'Mundo 1','slug':'m1','status':'open','is_active':True,'settings':{'worldSpeed':8,'unitSpeed':3,'mapRadius':35},'max_players':50,'season_number':1,'created_at':now}],
 'players':[{'world_id':w,'user_id':u,'player_name':'Jogador Teste','email':'teste@example.com','points':12000,'crowns':1500,'academy_coins':25,'is_suspended':False,'last_seen_at':now,'last_sign_in_at':now,'save_updated_at':now,'village_count':1,'hero':{},'inventory':{},'flags_inventory':{},'premium':{},'research':{},'control':{'status':'active'}}],
 'villages':[{'id':v,'world_id':w,'owner_user_id':u,'owner_kind':'player','owner_name':'Jogador Teste','tribe_name':'LOBOS','name':'Aldeia Teste','x':500,'y':500,'points':12000,'loyalty':100,'resources':{'wood':12000,'clay':11000,'iron':10000},'units':{'spear':200,'sword':100,'axe':250,'light':50},'buildings':{'main':15,'barracks':12,'stable':8,'smith':10,'market':10,'farm':18,'warehouse':18,'wall':12},'supports':[],'unit_research':{},'scavenging':{},'build_queue':[],'recruit_queue':[],'unit_research_queue':[]}],
 'nodes':[{'id':'44444444-4444-4444-8444-444444444444','world_id':w,'type':'merchant','x':503,'y':499,'level':7,'available':True,'state':{'name':'Mercadora','price':145,'itemId':'resource_chest'}}],
 'events':[{'id':'55555555-5555-4555-8555-555555555555','world_id':w,'name':'Ataque da Horda','template_key':'ataque_horda','category':'combat','status':'active','starts_at':now,'ends_at':'2026-08-18T20:50:00Z','config':{},'rewards':{}}],
 'monsters':[{'id':'66666666-6666-4666-8666-666666666666','world_id':w,'name':'Colosso da Fronteira','template_key':'colosso_fronteira','monster_type':'event_boss','level':10,'x':504,'y':502,'hp':248641,'max_hp':250000,'status':'active','description':'Boss','abilities':{},'rewards':{},'spawn_at':now}],
 'eventTemplates':[{'key':'ataque_horda','name':'Ataque da Horda','category':'combat','description':'Evento','enabled':True,'duration_hours':24,'config':{},'rewards':{}}],
 'monsterTemplates':[{'key':'colosso_fronteira','name':'Colosso','family':'golem','tier':'world_boss','default_level':10,'base_hp':250000,'description':'Boss','abilities':{},'rewards':{},'enabled':True}],
 'commands':[],'attacks':[],'onlineSupports':[],
 'tribes':[{'id':'77777777-7777-4777-8777-777777777777','world_id':w,'name':'Lobos','tag':'LOBOS','level':4,'xp':1000,'treasury':{},'technologies':{},'diplomacy':{}}],
 'tribeMembers':[{'tribe_id':'77777777-7777-4777-8777-777777777777','user_id':u,'role':'leader','joined_at':now}],
 'offers':[{'id':'88888888-8888-4888-8888-888888888888','world_id':w,'seller_user_id':u,'seller_village_id':v,'give_resource':'wood','give_amount':1000,'get_resource':'iron','get_amount':800,'status':'open','created_at':now}],
 'messages':[{'id':'99999999-9999-4999-8999-999999999999','world_id':w,'recipient_user_id':u,'subject':'Mensagem ADM','body':'Teste','unread':True,'created_at':now}],
 'reports':[{'id':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','world_id':w,'user_id':u,'title':'Relatório','body':'Teste','type':'battle','created_at':now}],
 'entitlements':[{'id':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','world_id':w,'user_id':u,'kind':'item','code':'resource_chest','name':'Baú','bonus':{},'active':True,'granted_at':now}],
 'controls':[],'rtWorldEvents':[],'eventProgress':[],'eventRewards':[],
 'auditLog':[{'id':'cccccccc-cccc-4ccc-8ccc-cccccccccccc','admin_id':'dddddddd-dddd-4ddd-8ddd-dddddddddddd','action':'village_patch_full','world_id':w,'target_user_id':u,'payload':{},'created_at':now}],
 'seasons':[{'id':'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','world_id':w,'name':'Temporada 1','status':'active','starts_at':now,'ends_at':'2026-08-26T20:50:00Z','config':{'rewards':{}}}],
 'ratings':[{'season_id':'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','user_id':u,'rating':1024,'wins':1,'losses':0,'matches':1,'streak':1,'updated_at':now}],
 'matches':[],'saves':[],
 'adminSessions':[{'id':'ffffffff-ffff-4fff-8fff-ffffffffffff','admin_id':'dddddddd-dddd-4ddd-8ddd-dddddddddddd','expires_at':'2026-08-18T20:50:00Z','created_at':now,'last_seen_at':now}],
 'adminAccounts':[{'id':'dddddddd-dddd-4ddd-8ddd-dddddddddddd','username':'reinos_admin','role':'superadmin','active':True,'display_name':'Administrador','created_at':now,'last_login_at':now,'updated_at':now}],
 'monsterHits':[],'worldStats':[{'world_id':w,'players':3,'online':2,'villages':726,'player_villages':3,'barbarians':700,'ai':23,'nodes':12,'monsters':5,'events':3,'commands':2,'attacks':1,'tribes':1,'offers':2,'messages':4,'reports':6,'points':22000}],
 'dbCounts':{'worlds':1,'players':3,'villages':726,'nodes':12,'monsters':5,'events':3,'commands':2,'attacks':1,'tribes':1,'market_offers':2,'messages':4,'reports':6,'admin_sessions':1,'audit':25}}
def admin(d):
 html=urllib.request.urlopen(PUBLIC+'?admfast=1',timeout=30).read().decode()
 needle="window.addEventListener('beforeunload', () => saveState(true));";html=html.replace(needle,"window.__A={renderIntegratedAdmin,RTADMIN};\n"+needle,1)
 wd=OUT/'site';wd.mkdir(exist_ok=True);(wd/'index.html').write_text(html,encoding='utf-8')
 p=subprocess.Popen(['python','-m','http.server','8766','--bind','127.0.0.1','--directory',str(wd)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  time.sleep(.5);d.get('http://127.0.0.1:8766/index.html');ready(d)
  d.execute_script("window.__orig=window.fetch.bind(window);window.fetch=(u,o)=>String(u).includes('rt-admin-support-v64')?Promise.resolve(new Response(JSON.stringify({supports:[]}),{status:200,headers:{'Content-Type':'application/json'}})):window.__orig(u,o);window.__A.RTADMIN.token='audit';window.__A.RTADMIN.info={username:'reinos_admin',role:'superadmin'}")
  m=mock();tabs=['overview','worlds','players','villages','mapops','events','ranked','combat','market','tribes','comms','rewards','database','audit','security']
  for t in tabs:
   try:d.execute_script("window.__A.RTADMIN.ui.tab=arguments[0];window.__A.renderIntegratedAdmin(arguments[1],true)",t,m);time.sleep(.25);snap(d,'ADM','tab_'+t)
   except Exception as e:M.append({'kind':'ERRO','name':'adm_'+t,'file':'','notes':str(e)})
  for tab,sel,n in [('players','[data-rt64-edit-player]','editar_jogador'),('players','[data-rt64-password]','senha_jogador'),('villages','[data-rt64-edit-village]','editar_aldeia'),('events','[data-rt64-edit-monster]','editar_monstro')]:
   try:d.execute_script("window.__A.RTADMIN.ui.tab=arguments[0];window.__A.renderIntegratedAdmin(arguments[1],true)",tab,m);time.sleep(.2);click(d,sel);snap(d,'ADM_MODAL',n);d.execute_script("document.querySelectorAll('.rt60-admin-modal').forEach(x=>x.remove())")
   except Exception as e:M.append({'kind':'ERRO','name':n,'file':'','notes':str(e)})
 finally:p.terminate()
def main():
 o=Options();o.add_argument('--headless=new');o.add_argument('--window-size=1600,1000');o.add_argument('--disable-gpu');o.add_argument('--ignore-certificate-errors')
 d=webdriver.Edge(options=o)
 try:
  try:game(d)
  except Exception as e:M.append({'kind':'ERRO','name':'fase_jogo','file':'','notes':repr(e)});print('GAMEERR',repr(e))
  try:admin(d)
  except Exception as e:M.append({'kind':'ERRO','name':'fase_adm','file':'','notes':repr(e)});print('ADMERR',repr(e))
 finally:d.quit()
 (OUT/'manifest.json').write_text(json.dumps(M,ensure_ascii=False,indent=2),encoding='utf-8')
 (OUT/'INDICE_PRINTS_RT77.md').write_text('# PRINTS RT77\n\n'+'\n'.join(f"{i+1:03d}. {x['kind']} — {x['name']} — {x['file'] or 'SEM PRINT'} — {x['notes']}" for i,x in enumerate(M)),encoding='utf-8')
 print('TOTAL',len([x for x in M if x['file']]),'ERROS',len([x for x in M if x['kind']=='ERRO']))
if __name__=='__main__':main()
