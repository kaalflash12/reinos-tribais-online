from pathlib import Path
import os, json, time, subprocess, urllib.request, textwrap, traceback
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.edge.options import Options as EdgeOptions
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

PUBLIC='https://kaalflash12.github.io/reinos-tribais-online/'
OUT=Path(os.environ.get('RUNNER_TEMP', '/tmp'))/'RT77_PRINTS_COMPLETOS'
OUT.mkdir(parents=True, exist_ok=True)
manifest=[]

def slug(s):
    return ''.join(c if c.isalnum() or c in '-_' else '_' for c in s)[:120]

def add(kind,name,file,notes=''):
    manifest.append({'kind':kind,'name':name,'file':file.name,'notes':notes})

def wait_ready(d, timeout=25):
    WebDriverWait(d,timeout).until(lambda x: x.execute_script('return document.readyState')=='complete')
    time.sleep(1.2)

def shot(d,kind,name,notes=''):
    try:
        w=max(1500, int(d.execute_script('return Math.max(document.documentElement.scrollWidth, document.body.scrollWidth, 1500)')))
        h=max(900, int(d.execute_script('return Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, 900)')))
        d.set_window_size(min(w,1900), min(h,6500))
        time.sleep(.25)
    except Exception:
        pass
    fn=OUT/f'{len(manifest)+1:03d}_{slug(kind)}_{slug(name)}.png'
    d.save_screenshot(str(fn))
    add(kind,name,fn,notes)
    return fn

def click_js(d,sel):
    ok=d.execute_script("const e=document.querySelector(arguments[0]); if(e){e.click(); return true} return false",sel)
    if not ok: raise RuntimeError(f'Elemento não encontrado: {sel}')
    time.sleep(.8)

def game_capture(d):
    d.get(PUBLIC+'?rt77-print-audit=1')
    wait_ready(d)
    shot(d,'JOGO','00_entrada','Tela pública RT77 antes de entrar.')
    click_js(d,'[data-play-offline]')
    shot(d,'JOGO','01_novo_reino','Configuração do mundo local.')
    d.execute_script("""
      const f=document.querySelector('#start-form');
      if(f){
        f.elements.playerName.value='Auditoria RT77';
        f.elements.villageName.value='Aldeia de Teste RT77';
        f.elements.difficulty.value='normal';
        f.elements.mapRadius.value='16';
        f.elements.startProfile.value='military';
        f.requestSubmit();
      }
    """)
    time.sleep(3)
    shot(d,'JOGO','02_visao_geral','Aldeia criada em modo local; overview real do jogo.')

    views=[
      ('systems','Central de Sistemas'),('buildings','Edifícios'),('recruit','Recrutamento'),('research','Pesquisas'),
      ('rally','Praça de Reunião'),('academy','Academia'),('hero','Paladino'),('arsenal','Arsenal'),('map','Mapa'),
      ('commands','Comandos'),('missions','Missões'),('reports','Relatórios'),('messages','Mensagens'),('market','Mercado'),
      ('inventory','Inventário'),('premium','Premium'),('manager','Gerenciador'),('flags','Bandeiras'),('ranking','Ranking'),
      ('tribe','Tribo'),('help','Ajuda'),('settings','Configurações'),('events','Eventos'),('ranked','Ranked')
    ]
    for view,label in views:
        try:
            click_js(d,f'[data-view="{view}"]')
            shot(d,'JOGO',f'pagina_{view}',f'Página/função: {label}.')
        except Exception as e:
            manifest.append({'kind':'ERRO','name':f'pagina_{view}','file':'','notes':str(e)})

    try:
        click_js(d,'[data-view="overview"]')
    except Exception:
        d.refresh(); time.sleep(2)
    keys=d.execute_script("return [...new Set(Array.from(document.querySelectorAll('[data-open-building]')).map(e=>e.dataset.openBuilding).filter(Boolean))]") or []
    if len(keys)<19:
        try: click_js(d,'[data-view="buildings"]')
        except: pass
        more=d.execute_script("return [...new Set(Array.from(document.querySelectorAll('[data-open-building]')).map(e=>e.dataset.openBuilding).filter(Boolean))]") or []
        keys=list(dict.fromkeys(keys+more))
    for k in keys:
        try:
            click_js(d,f'[data-open-building="{k}"]')
            shot(d,'EDIFICIO',k,f'Detalhe funcional do edifício {k}.')
            try: click_js(d,'[data-view="buildings"]')
            except: pass
        except Exception as e:
            manifest.append({'kind':'ERRO','name':f'edificio_{k}','file':'','notes':str(e)})

    d.get(PUBLIC+'?rt77-print-auth=1'); wait_ready(d); click_js(d,'[data-entry-online]'); time.sleep(.8)
    shot(d,'CONTA','login_cadastro','Login e criação de conta.')
    try:
        click_js(d,'[data-forgot-password]'); shot(d,'CONTA','recuperacao_codigo','Recuperação por código e troca de senha.')
    except Exception as e:
        manifest.append({'kind':'ERRO','name':'recuperacao_codigo','file':'','notes':str(e)})


def admin_mock_data():
    now='2026-08-17T20:10:00Z'; wid='11111111-1111-4111-8111-111111111111'; uid='22222222-2222-4222-8222-222222222222'; vid='33333333-3333-4333-8333-333333333333'
    village={'id':vid,'world_id':wid,'owner_user_id':uid,'owner_kind':'player','owner_name':'Jogador Auditoria','tribe_name':'LOBOS','name':'Aldeia Administrada','x':500,'y':500,'points':12345,'loyalty':100,'resources':{'wood':12000,'clay':11000,'iron':10000},'units':{'spear':250,'sword':120,'axe':300,'light':70,'ram':15,'catapult':8},'buildings':{'main':15,'barracks':12,'stable':8,'workshop':5,'smith':10,'market':10,'farm':18,'warehouse':18,'wall':12,'academy':1},'supports':[],'unit_research':{},'scavenging':{},'militia_called':False,'build_queue':[],'recruit_queue':[],'unit_research_queue':[]}
    player={'world_id':wid,'user_id':uid,'player_name':'Jogador Auditoria','email':'auditoria@example.com','points':12345,'crowns':1500,'academy_coins':25,'is_suspended':False,'last_seen_at':now,'last_sign_in_at':now,'save_updated_at':now,'village_count':1,'hero':{'name':'Paladino Auditoria','level':12},'inventory':{'resource_chest':3},'flags_inventory':{},'premium':{},'research':{},'control':{'status':'active'}}
    return {
      'version':77,'generated_at':now,
      'worlds':[{'id':wid,'name':'Mundo 1 — Auditoria','slug':'mundo-1','status':'open','is_active':True,'settings':{'worldSpeed':8,'unitSpeed':3,'mapRadius':35},'max_players':50,'season_number':1,'created_at':now}],
      'players':[player],'villages':[village],
      'nodes':[{'id':'44444444-4444-4444-8444-444444444444','world_id':wid,'type':'merchant','x':503,'y':499,'level':7,'available':True,'state':{'name':'Mercadora da Rota Dourada','price':145,'itemId':'production_banner'}}],
      'events':[{'id':'55555555-5555-4555-8555-555555555555','world_id':wid,'name':'Ataque da Horda','template_key':'ataque_horda','category':'combat','status':'active','starts_at':now,'ends_at':'2026-08-18T20:10:00Z','config':{'spawn_monster':True},'rewards':{'crowns':100}}],
      'monsters':[{'id':'66666666-6666-4666-8666-666666666666','world_id':wid,'name':'Colosso da Fronteira','template_key':'colosso_fronteira','monster_type':'event_boss','level':10,'x':504,'y':502,'hp':248641,'max_hp':250000,'status':'active','description':'Boss mundial de auditoria','abilities':{},'rewards':{'crowns':50},'spawn_at':now}],
      'eventTemplates':[{'key':'ataque_horda','name':'Ataque da Horda','category':'combat','description':'Evento de ataque','enabled':True,'duration_hours':24,'config':{},'rewards':{}}],
      'monsterTemplates':[{'key':'colosso_fronteira','name':'Colosso da Fronteira','family':'golem','tier':'world_boss','default_level':10,'base_hp':250000,'description':'Boss mundial','abilities':{},'rewards':{},'enabled':True}],
      'commands':[{'id':'77777777-7777-4777-8777-777777777777','world_id':wid,'owner_user_id':uid,'source_village_id':vid,'target_village_id':'88888888-8888-4888-8888-888888888888','kind':'attack','troops':{'spear':50},'started_at':now,'arrives_at':'2026-08-17T21:10:00Z','resolved_at':None}],
      'attacks':[{'id':'99999999-9999-4999-8999-999999999999','world_id':wid,'attacker_user_id':uid,'source_village_id':vid,'target_village_id':'88888888-8888-4888-8888-888888888888','sent_at':now,'arrives_at':'2026-08-17T21:10:00Z','status':'marching','troops':{'axe':100}}],
      'onlineSupports':[{'id':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','world_id':wid,'owner_user_id':uid,'source_village_id':vid,'target_village_id':'88888888-8888-4888-8888-888888888888','troops':{'spear':40},'status':'arrived','arrives_at':now}],
      'tribes':[{'id':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','world_id':wid,'name':'Lobos do Norte','tag':'LOBOS','level':4,'xp':1200,'treasury':{'wood':1000},'technologies':{},'diplomacy':{}}],
      'tribeMembers':[{'tribe_id':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','user_id':uid,'role':'leader','joined_at':now}],
      'offers':[{'id':'cccccccc-cccc-4ccc-8ccc-cccccccccccc','world_id':wid,'seller_user_id':uid,'seller_village_id':vid,'give_resource':'wood','give_amount':1000,'get_resource':'iron','get_amount':800,'status':'open','created_at':now}],
      'messages':[{'id':'dddddddd-dddd-4ddd-8ddd-dddddddddddd','world_id':wid,'sender_user_id':None,'recipient_user_id':uid,'subject':'Mensagem administrativa','body':'Mensagem de teste','unread':True,'created_at':now}],
      'reports':[{'id':'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','world_id':wid,'user_id':uid,'title':'Relatório de batalha','body':'Vitória de auditoria','type':'battle','created_at':now}],
      'entitlements':[{'id':'ffffffff-ffff-4fff-8fff-ffffffffffff','world_id':wid,'user_id':uid,'kind':'item','code':'resource_chest','name':'Baú de Recursos','bonus':{},'active':True,'granted_at':now,'expires_at':None}],
      'controls':[{'world_id':wid,'user_id':uid,'status':'active','muted_until':None,'note':'Conta normal','updated_at':now}],
      'rtWorldEvents':[{'id':'12121212-1212-4212-8212-121212121212','world_id':wid,'template_key':'ataque_horda','code':'auto_ataque_horda_20260817','name':'Ataque da Horda','category':'combat','description':'Evento RT','status':'active','starts_at':now,'ends_at':'2026-08-18T20:10:00Z','config':{},'rewards':{}}],
      'eventProgress':[{'event_id':'12121212-1212-4212-8212-121212121212','user_id':uid,'score':250,'counters':{'hits':3},'claimed':{},'updated_at':now}],
      'eventRewards':[{'id':'13131313-1313-4313-8313-131313131313','world_id':wid,'event_id':'12121212-1212-4212-8212-121212121212','user_id':uid,'rank':3,'reward':{'crowns':25,'academy_coins':2},'status':'pending','expires_at':'2026-09-17T20:10:00Z','created_at':now}],
      'auditLog':[{'id':'14141414-1414-4414-8414-141414141414','admin_id':'15151515-1515-4515-8515-151515151515','action':'village_patch_full','world_id':wid,'target_user_id':uid,'payload':{'fields':['resources','units']},'created_at':now}],
      'seasons':[{'id':'16161616-1616-4616-8616-161616161616','world_id':wid,'name':'Temporada Ranqueada Inaugural','status':'active','starts_at':now,'ends_at':'2026-08-26T20:10:00Z','config':{'base_rating':1000,'rewards':{}}}],
      'ratings':[{'season_id':'16161616-1616-4616-8616-161616161616','user_id':uid,'rating':1024,'wins':1,'losses':0,'matches':1,'streak':1,'updated_at':now}],
      'matches':[{'id':'17171717-1717-4717-8717-171717171717','season_id':'16161616-1616-4616-8616-161616161616','world_id':wid,'user_a':uid,'user_b':'18181818-1818-4818-8818-181818181818','winner_user_id':uid,'rating_delta_a':24,'rating_delta_b':-24,'created_at':now}],
      'saves':[{'user_id':uid,'world_id':wid,'updated_at':now}],
      'adminSessions':[{'id':'19191919-1919-4919-8919-191919191919','admin_id':'15151515-1515-4515-8515-151515151515','expires_at':'2026-08-18T20:10:00Z','created_at':now,'last_seen_at':now}],
      'adminAccounts':[{'id':'15151515-1515-4515-8515-151515151515','username':'reinos_admin','role':'superadmin','active':True,'display_name':'Administrador Principal','created_at':now,'last_login_at':now,'updated_at':now}],
      'monsterHits':[{'id':'20202020-2020-4020-8020-202020202020','world_id':wid,'monster_id':'66666666-6666-4666-8666-666666666666','user_id':uid,'damage':1359,'created_at':now}],
      'worldStats':[{'world_id':wid,'players':3,'online':2,'villages':726,'player_villages':3,'barbarians':700,'ai':23,'nodes':12,'monsters':5,'events':3,'commands':2,'attacks':1,'tribes':1,'offers':2,'messages':4,'reports':6,'points':22000}],
      'dbCounts':{'worlds':1,'players':3,'villages':726,'nodes':12,'monsters':5,'events':3,'commands':2,'attacks':1,'tribes':1,'tribe_members':2,'market_offers':2,'messages':4,'reports':6,'entitlements':5,'rt_world_events':8,'event_progress':4,'event_rewards':2,'ranked_seasons':1,'ranked_ratings':3,'ranked_matches':2,'admin_sessions':1,'audit':25,'monster_hits':8}
    }

def admin_capture(d):
    html=urllib.request.urlopen(PUBLIC+'?source=admin-audit',timeout=30).read().decode('utf-8')
    needle="window.addEventListener('beforeunload', () => saveState(true));"
    if needle not in html:
        raise RuntimeError('Não encontrei ponto seguro para expor renderer admin.')
    html=html.replace(needle,"window.__RT77_AUDIT_ADMIN={renderIntegratedAdmin,RTADMIN};\n"+needle,1)
    work=OUT/'_audit_site'; work.mkdir(exist_ok=True)
    (work/'index.html').write_text(html,encoding='utf-8')
    server=subprocess.Popen(['python','-m','http.server','8765','--bind','127.0.0.1','--directory',str(work)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        time.sleep(1)
        d.get('http://127.0.0.1:8765/index.html?rt77-admin-audit=1'); wait_ready(d)
        mock=admin_mock_data()
        d.execute_script("window.__RT77_AUDIT_ADMIN.RTADMIN.token='audit-ui-only';window.__RT77_AUDIT_ADMIN.RTADMIN.info={username:'reinos_admin',role:'superadmin'};")
        tabs=[('overview','Visão geral'),('worlds','Mundos'),('players','Contas e jogadores'),('villages','Aldeias'),('mapops','Mapa'),('events','Eventos e bosses'),('ranked','Ranked'),('combat','Combate'),('market','Mercado'),('tribes','Tribos'),('comms','Mensagens e relatórios'),('rewards','Premium e recompensas'),('database','Banco'),('audit','Auditoria'),('security','Segurança')]
        for tab,label in tabs:
            d.execute_script("window.__RT77_AUDIT_ADMIN.RTADMIN.ui.tab=arguments[0]; return window.__RT77_AUDIT_ADMIN.renderIntegratedAdmin(arguments[1],true);",tab,mock)
            time.sleep(.8)
            shot(d,'ADM',f'tab_{tab}',f'Interface administrativa real RT77 — {label}. Dados de prova isolados; nenhum write é enviado ao servidor.')
        d.execute_script("window.__RT77_AUDIT_ADMIN.RTADMIN.ui.tab='players'; return window.__RT77_AUDIT_ADMIN.renderIntegratedAdmin(arguments[0],true);",mock); time.sleep(.5)
        for sel,name in [('[data-rt64-edit-player]','editar_jogador'),('[data-rt64-password]','senha_jogador'),('[data-rt64-recovery]','recovery_jogador')]:
            try:
                click_js(d,sel); shot(d,'ADM_MODAL',name,'Modal administrativo aberto sem confirmar alteração.');
                d.execute_script("document.querySelectorAll('.rt60-admin-modal').forEach(x=>x.remove())")
            except Exception as e: manifest.append({'kind':'ERRO','name':name,'file':'','notes':str(e)})
        d.execute_script("window.__RT77_AUDIT_ADMIN.RTADMIN.ui.tab='villages'; return window.__RT77_AUDIT_ADMIN.renderIntegratedAdmin(arguments[0],true);",mock); time.sleep(.5)
        try:
            click_js(d,'[data-rt64-edit-village]'); shot(d,'ADM_MODAL','editar_aldeia_integral','Editor integral de aldeia: identidade, posição, economia, tropas, edifícios e estado.'); d.execute_script("document.querySelectorAll('.rt60-admin-modal').forEach(x=>x.remove())")
        except Exception as e: manifest.append({'kind':'ERRO','name':'editar_aldeia_integral','file':'','notes':str(e)})
        d.execute_script("window.__RT77_AUDIT_ADMIN.RTADMIN.ui.tab='events'; return window.__RT77_AUDIT_ADMIN.renderIntegratedAdmin(arguments[0],true);",mock); time.sleep(.5)
        try:
            click_js(d,'[data-rt64-edit-monster]'); shot(d,'ADM_MODAL','editar_monstro_boss','Editor administrativo de monstro/boss.'); d.execute_script("document.querySelectorAll('.rt60-admin-modal').forEach(x=>x.remove())")
        except Exception as e: manifest.append({'kind':'ERRO','name':'editar_monstro_boss','file':'','notes':str(e)})
    finally:
        server.terminate()

def main():
    opts=EdgeOptions(); opts.add_argument('--headless=new'); opts.add_argument('--disable-gpu'); opts.add_argument('--window-size=1600,1000'); opts.add_argument('--no-first-run'); opts.add_argument('--disable-dev-shm-usage'); opts.add_argument('--ignore-certificate-errors')
    d=webdriver.Edge(options=opts)
    try:
        game_capture(d)
        admin_capture(d)
    finally:
        d.quit()
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# ÍNDICE DE PRINTS — RT77','',f'Total de registros: **{len(manifest)}**','', '> ADM: os screenshots usam o renderer administrativo real da RT77 em uma cópia temporária de auditoria, com dados de prova isolados. Nenhuma alteração administrativa é confirmada no servidor durante a captura.','']
    for i,x in enumerate(manifest,1): lines.append(f"{i:03d}. **{x['kind']} — {x['name']}** — `{x['file'] or 'SEM ARQUIVO'}` — {x['notes']}")
    (OUT/'INDICE_PRINTS_RT77.md').write_text('\n'.join(lines),encoding='utf-8')
    print('OUT',OUT,'screens',sum(1 for x in manifest if x['file']))
if __name__=='__main__':
    try: main()
    except Exception:
        traceback.print_exc(); raise
