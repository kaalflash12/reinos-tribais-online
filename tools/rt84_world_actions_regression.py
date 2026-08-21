from pathlib import Path
import os,json,time
from selenium import webdriver
from selenium.webdriver.edge.options import Options
from selenium.webdriver.support.ui import WebDriverWait

BASE=os.environ.get('RT84_URL','http://127.0.0.1:8765/')
OUT=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'RT84_WORLD_ACTIONS_PROOF'
OUT.mkdir(parents=True,exist_ok=True)
checks=[]

def req(d,name,js,timeout=25):
    WebDriverWait(d,timeout).until(lambda x: bool(x.execute_script(js)))
    ok=bool(d.execute_script(js)); checks.append({'name':name,'pass':ok})
    if not ok: raise AssertionError(name)

def shot(d,name):
    p=OUT/f'{len(list(OUT.glob("*.png")))+1:02d}_{name}.png'; d.save_screenshot(str(p)); return p.name

def main():
    global checks
    opt=Options(); opt.page_load_strategy='eager'; opt.add_argument('--headless=new'); opt.add_argument('--disable-gpu'); opt.add_argument('--no-sandbox'); opt.add_argument('--window-size=1600,1000')
    d=webdriver.Edge(options=opt); proof={'pass':False,'checks':checks,'screenshots':[]}
    try:
        d.get(BASE+'?rt84-world-audit=1')
        req(d,'RT84 loaded','return !!window.__RT84_WORLD_ACTIONS__ && !!window.RT84World')
        d.execute_script("document.querySelector('[data-play-offline]')?.click()")
        time.sleep(.5)
        d.execute_script("""
          const f=document.querySelector('#start-form');
          if(f){f.elements.playerName.value='Auditoria RT84';f.elements.villageName.value='Aldeia RT84';f.elements.difficulty.value='normal';f.elements.mapRadius.value='16';f.elements.startProfile.value='military';f.requestSubmit();}
        """)
        req(d,'game started','return !!window.RT76?.state?.()')
        d.execute_script("""
          const s=RT76.state(),v=RT76.test.getActiveVillage();
          v.resources={wood:10000,clay:10000,iron:10000,lastUpdate:Date.now()}; v.buildings.warehouse=20;
          v.units.spy=300; v.units.spear=300; s.player.premium={crowns:500,buffs:{}}; s.player.inventory={};
          s.rt84={day:new Date().toISOString().slice(0,10),daily:0,actionUntil:0,reports:[]};
          const ruins={id:'rt84_ruins_ok',type:'ruins',level:3,x:v.x+2,y:v.y+1,available:true,respawnAt:0,state:{}};
          const ruinsFail={id:'rt84_ruins_fail',type:'rare_ruins',level:6,x:v.x+3,y:v.y+2,available:true,respawnAt:0,state:{}};
          const merchant={id:'rt84_merchant',type:'merchant',level:2,x:v.x+1,y:v.y+1,available:true,respawnAt:0,state:{itemId:'spyglass',price:90}};
          s.world.nodes.push(ruins,ruinsFail,merchant); RT76.save();
        """)
        success=d.execute_script("""
          const old=Math.random;Math.random=()=>0;const s=RT76.state(),v=RT76.test.getActiveVillage(),node=s.world.nodes.find(x=>x.id==='rt84_ruins_ok');
          const before={wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron,crowns:s.player.premium.crowns,inv:JSON.stringify(s.player.inventory)};
          let r;try{r=RT84World.offline(node,'main')}finally{Math.random=old}
          return {r,before,after:{wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron,crowns:s.player.premium.crowns,inv:JSON.stringify(s.player.inventory)},daily:s.rt84.daily,reports:s.rt84.reports.length,available:node.available,respawnAt:node.respawnAt};
        """)
        cost=success['r']['cost']
        checks += [
          {'name':'ruins consumes supplies','pass':success['after']['wood']-success['before']['wood'] < int(success['r']['reward']['wood']) and int(cost['wood'])>0 and int(cost['clay'])>0 and int(cost['iron'])>0},
          {'name':'ruins reward only after success','pass':success['r']['success'] is True and success['after']['crowns']>success['before']['crowns']},
          {'name':'interaction report stored','pass':success['reports']>=1 and success['daily']==1},
          {'name':'target cooldown persisted','pass':success['available'] is False and success['respawnAt']>0},
        ]
        spam=d.execute_script("""
          const s=RT76.state(),node=s.world.nodes.find(x=>x.id==='rt84_ruins_ok');try{RT84World.offline(node,'main');return {blocked:false,msg:''}}catch(e){return {blocked:true,msg:String(e.message||e)}}
        """)
        checks.append({'name':'global or target cooldown blocks spam','pass':spam['blocked'] and ('Aguarde' in spam['msg'] or 'recarga' in spam['msg'].lower()),'detail':spam['msg']})
        failure=d.execute_script("""
          const old=Math.random;Math.random=()=>.999;const s=RT76.state(),v=RT76.test.getActiveVillage(),node=s.world.nodes.find(x=>x.id==='rt84_ruins_fail');s.rt84.actionUntil=0;
          const before={wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron,crowns:s.player.premium.crowns,inv:JSON.stringify(s.player.inventory)};
          let r;try{r=RT84World.offline(node,'main')}finally{Math.random=old}
          return {r,before,after:{wood:v.resources.wood,clay:v.resources.clay,iron:v.resources.iron,crowns:s.player.premium.crowns,inv:JSON.stringify(s.player.inventory)},daily:s.rt84.daily};
        """)
        checks += [
          {'name':'failed expedition consumes supplies','pass':failure['r']['success'] is False and failure['after']['wood']<failure['before']['wood'] and failure['after']['clay']<failure['before']['clay'] and failure['after']['iron']<failure['before']['iron']},
          {'name':'failed expedition gives no prize','pass':failure['after']['crowns']==failure['before']['crowns'] and failure['after']['inv']==failure['before']['inv']},
        ]
        merchant=d.execute_script("""
          const s=RT76.state(),v=RT76.test.getActiveVillage(),node=s.world.nodes.find(x=>x.id==='rt84_merchant');s.rt84.actionUntil=0;
          const before={crowns:s.player.premium.crowns,inventory:{...(s.player.inventory||{})},wood:v.resources.wood};
          const r=RT84World.offline(node,'buy');return {configuredItem:node.state.itemId,r,before,after:{crowns:s.player.premium.crowns,inventory:{...(s.player.inventory||{})},wood:v.resources.wood}};
        """)
        bought=merchant['r']['reward'].get('item')
        before_qty=int(merchant['before']['inventory'].get(bought,0)) if bought else 0
        after_qty=int(merchant['after']['inventory'].get(bought,0)) if bought else 0
        checks += [
          {'name':'merchant charges crowns','pass':merchant['after']['crowns']<merchant['before']['crowns']},
          {'name':'merchant honors configured offer','pass':bought==merchant['configuredItem'],'detail':json.dumps({'configured':merchant['configuredItem'],'returned':bought},ensure_ascii=False)},
          {'name':'merchant gives exactly purchased item','pass':bool(bought) and after_qty==before_qty+1,'detail':json.dumps({'item':bought,'before':merchant['before']['inventory'],'after':merchant['after']['inventory']},ensure_ascii=False)},
          {'name':'merchant also consumes expedition supplies','pass':merchant['after']['wood']<merchant['before']['wood']},
        ]
        daily=d.execute_script("""
          const s=RT76.state(),node=s.world.nodes.find(x=>x.id==='rt84_merchant');s.rt84.actionUntil=0;s.rt84.daily=30;node.available=true;node.respawnAt=0;node.state.rt84CooldownUntil=0;
          try{RT84World.offline(node,'buy');return {blocked:false,msg:''}}catch(e){return {blocked:true,msg:String(e.message||e)}}
        """)
        checks.append({'name':'daily limit blocks farming','pass':daily['blocked'] and '30' in daily['msg'],'detail':daily['msg']})
        d.execute_script("""
          const s=RT76.state(),node=s.world.nodes.find(x=>x.id==='rt84_ruins_ok');s.rt84.daily=0;s.rt84.actionUntil=0;node.available=true;node.respawnAt=0;node.state.rt84CooldownUntil=0;RT76.test.render?.();
        """)
        d.execute_script("document.querySelector('[data-view=\"map\"]')?.click()")
        time.sleep(.6)
        checks.append({'name':'map explanation exposes cost/chance/limit','pass':bool(d.execute_script("const s=RT76.state(),n=s.world.nodes.find(x=>x.id==='rt84_ruins_ok'),txt=RT84World.details(n);return /custo/i.test(txt)&&/chance/i.test(txt)&&/30\\/dia/i.test(txt)"))})
        proof['screenshots'].append(shot(d,'RT84_MAPA_INTERACOES'))
        failures=[x for x in checks if not x.get('pass')]
        proof['pass']=not failures;proof['failures']=failures
        (OUT/'PROVA_RT84_INTERACOES_REAIS.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'pass':proof['pass'],'checks':len(checks),'failures':len(failures)},ensure_ascii=False))
        if failures: raise SystemExit(2)
    except Exception as e:
        proof['error']=repr(e);proof['failures']=[x for x in checks if not x.get('pass')]
        try: proof['screenshots'].append(shot(d,'FAIL_RT84'))
        except Exception: pass
        (OUT/'PROVA_RT84_INTERACOES_REAIS.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2),encoding='utf-8')
        raise
    finally:d.quit()

if __name__=='__main__':main()
