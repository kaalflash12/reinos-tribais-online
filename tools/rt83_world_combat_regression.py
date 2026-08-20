from pathlib import Path
import os,json,time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT83_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT83_WORLD_COMBAT_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
checks=[]

def req(d,name,js,timeout=25):
    WebDriverWait(d,timeout).until(lambda x: bool(x.execute_script(js)))
    ok=bool(d.execute_script(js)); checks.append({'name':name,'pass':ok})
    if not ok: raise AssertionError(name)

def shot(d,name):
    p=OUT/f'{len(list(OUT.glob("*.png")))+1:02d}_{name}.png';d.save_screenshot(str(p));return p.name

def main():
    global checks
    opt=Options();opt.page_load_strategy='eager';opt.add_argument('--headless=new');opt.add_argument('--disable-gpu');opt.add_argument('--no-sandbox');opt.add_argument('--window-size=1600,1000')
    d=webdriver.Edge(options=opt); proof={'pass':False,'checks':checks,'screenshots':[]}
    try:
        d.get(BASE+'?rt83-combat-audit=1')
        req(d,'RT83 loaded','return !!window.__RT83_WORLD_COMBAT__ && !!window.RT83WorldCombat')
        d.execute_script("document.querySelector('[data-play-offline]')?.click()")
        time.sleep(.5)
        d.execute_script("""
          const f=document.querySelector('#start-form');
          if(f){f.elements.playerName.value='Auditoria RT83';f.elements.villageName.value='Aldeia RT83';f.elements.difficulty.value='normal';f.elements.mapRadius.value='16';f.elements.startProfile.value='military';f.requestSubmit();}
        """)
        req(d,'game started','return !!window.RT76?.state?.()')
        setup=d.execute_script("""
          const s=RT76.state(),v=RT76.test.getActiveVillage();
          v.units={spear:200,sword:30,axe:200,archer:0,spy:0,light:0,marcher:0,heavy:0,ram:0,catapult:0,paladin:0,noble:0,militia:0};
          v.resources={wood:99999,clay:99999,iron:99999,lastUpdate:Date.now()};v.buildings.warehouse=20;v.unitResearch={};
          const mon={id:'rt83_monster_test',type:'monsters',level:9,x:v.x+3,y:v.y+2,owner:'world',available:true,respawnAt:0,state:{name:'Hidra de Auditoria',hp:180000,max_hp:180000}};
          s.world.nodes.push(mon);s.rt83={worldActionUntil:0,reports:[]};RT76.save();
          return {wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron,spear:v.units.spear,axe:v.units.axe,hp:mon.state.hp};
        """)
        result=d.execute_script("""
          const s=RT76.state(),v=RT76.test.getActiveVillage(),n=s.world.nodes.find(x=>x.id==='rt83_monster_test');
          const r=RT83WorldCombat.offlineBattle(n,{spear:20,axe:20});
          return {r,wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron,spear:v.units.spear,axe:v.units.axe,hp:n.state.hp,reports:s.rt83.reports.length};
        """)
        loss=sum(int(x) for x in result['r']['losses'].values())
        loot=sum(int(result['r']['reward'].get(k,0)) for k in ('wood','clay','iron'))
        checks += [
          {'name':'monster damage persisted','pass':result['hp'] < setup['hp']},
          {'name':'supplies consumed','pass':result['wood'] < setup['wood'] and result['clay'] < setup['clay'] and result['iron'] < setup['iron']},
          {'name':'troop losses real','pass':loss>0 and (result['spear']<setup['spear'] or result['axe']<setup['axe'])},
          {'name':'defeat gives no loot','pass':result['r']['victory'] is False and loot==0},
          {'name':'battle report stored','pass':result['reports']>=1},
        ]
        spam=d.execute_script("""
          const s=RT76.state(),n=s.world.nodes.find(x=>x.id==='rt83_monster_test');
          try{RT83WorldCombat.offlineBattle(n,{spear:10,axe:10});return {blocked:false,msg:''}}catch(e){return {blocked:true,msg:String(e.message||e)}}
        """)
        checks.append({'name':'anti-spam cooldown','pass':spam['blocked'] and 'recarga' in spam['msg'].lower(),'detail':spam['msg']})
        resource=d.execute_script("""
          const s=RT76.state(),v=RT76.test.getActiveVillage();s.rt83.worldActionUntil=0;
          const node={id:'rt83_forest_test',type:'forest',level:4,x:v.x+1,y:v.y+1,owner:'world',available:true,respawnAt:0,state:{name:'Bosque de Auditoria',rt83GuardHp:1}};s.world.nodes.push(node);
          const before={wood:v.resources.wood,spear:v.units.spear,axe:v.units.axe};
          const r=RT83WorldCombat.offlineBattle(node,{spear:80,axe:80});
          return {r,before,after:{wood:v.resources.wood,spear:v.units.spear,axe:v.units.axe},owner:node.owner,available:node.available,respawnAt:node.respawnAt};
        """)
        rloss=sum(int(x) for x in resource['r']['losses'].values())
        checks += [
          {'name':'resource victory requires combat','pass':resource['r']['victory'] is True},
          {'name':'resource combat has casualties','pass':rloss>0},
          {'name':'resource node ownership persisted','pass':resource['owner']=='player' and resource['available'] is False and resource['respawnAt']>0},
          {'name':'resource loot capacity based','pass':int(resource['r']['reward'].get('wood',0))>0},
        ]
        d.execute_script("""
          const s=RT76.state(),v=RT76.test.getActiveVillage();s.rt83.worldActionUntil=0;const n=s.world.nodes.find(x=>x.id==='rt83_monster_test');n.state.rt83CooldownUntil=0;RT83WorldCombat.open(n,'main');
        """)
        req(d,'formation modal visible','return !!document.querySelector(".rt83-modal #rt83-expedition-form")')
        req(d,'formation explains losses and supplies',"return /baixas|perdidas/i.test(document.querySelector('.rt83-modal').innerText)&&/suprimentos/i.test(document.querySelector('.rt83-modal').innerText)")
        proof['screenshots'].append(shot(d,'RT83_FORMACAO_COMBATE'))
        failures=[x for x in checks if not x.get('pass')]
        proof['pass']=not failures;proof['failures']=failures
        (OUT/'PROVA_RT83_COMBATE_REAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'pass':proof['pass'],'checks':len(checks),'failures':len(failures)},ensure_ascii=False))
        if failures: raise SystemExit(2)
    except Exception as e:
        proof['error']=repr(e);proof['failures']=[x for x in checks if not x.get('pass')]
        try: proof['screenshots'].append(shot(d,'FAIL_RT83'))
        except Exception: pass
        (OUT/'PROVA_RT83_COMBATE_REAL.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        raise
    finally:
        d.quit()

if __name__=='__main__':main()
