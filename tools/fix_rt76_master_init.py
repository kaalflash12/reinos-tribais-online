from pathlib import Path
p=Path('rt76-master-plan.js')
s=p.read_text(encoding='utf-8')
marker='/* RT76_MASTER_BASE_INIT */'
if marker not in s:
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
p.write_text(s,encoding='utf-8')
print('RT76 master base init: OK')
