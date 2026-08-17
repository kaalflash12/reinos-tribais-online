from pathlib import Path
p=Path('rt76-master-plan.js')
s=p.read_text(encoding='utf-8')
base_marker='/* RT76_MASTER_BASE_INIT */'
if base_marker not in s:
    old="""    s.rt76||={};
    const m=s.rt76.master||=( {"""
    new="""    s.rt76||={};
    /* RT76_MASTER_BASE_INIT */
    s.rt76.scheduledCommands||=[];
    s.rt76.targetIntel||={};
    s.rt76.actionLog||=[];
    s.rt76.farm||={templates:{A:{spear:25},B:{axe:40,light:10},C:{light:40,spy:1}},cycleLimit:5};
    s.rt76.farm.templates||={A:{spear:25},B:{axe:40,light:10},C:{light:40,spy:1}};
    s.rt76.market||={minStock:{wood:5000,clay:5000,iron:5000},cycleLimit:3,autoEqualize:false,history:[]};
    s.rt76.market.minStock||={wood:5000,clay:5000,iron:5000};
    s.rt76.market.history||=[];
    s.rt76.manager||={researchPriority:[],autoScavenge:false,decisionLog:[],lastExtraRun:0};
    s.rt76.manager.researchPriority||=[];
    s.rt76.manager.decisionLog||=[];
    const m=s.rt76.master||=( {"""
    if old not in s:
        raise SystemExit('master ensure anchor not found')
    s=s.replace(old,new,1)

inject_marker='/* RT76_MASTER_INJECT_ENSURE */'
if inject_marker not in s:
    old="function inject(){const s=S(),p=document.querySelector('.content-panel');"
    new="function inject(){/* RT76_MASTER_INJECT_ENSURE */ ensure();const s=S(),p=document.querySelector('.content-panel');"
    if old not in s:
        raise SystemExit('master inject anchor not found')
    s=s.replace(old,new,1)

poll_marker='/* RT76_MASTER_STATE_WATCH */'
if poll_marker not in s:
    old="  ensure();inject();\n})();"
    new="  /* RT76_MASTER_STATE_WATCH */ setInterval(()=>{try{if(S())ensure()}catch(_){}},200);\n  ensure();inject();\n})();"
    if old not in s:
        raise SystemExit('master tail anchor not found')
    s=s.replace(old,new,1)

p.write_text(s,encoding='utf-8')
print('RT76 master base init + state watch: OK')
