from pathlib import Path


def patch(path, old, new):
    p = Path(path)
    s = p.read_text(encoding='utf-8')
    if new in s:
        print(f'already patched: {path}')
        return
    if old not in s:
        raise SystemExit(f'pattern missing in {path}: {old[:100]}')
    p.write_text(s.replace(old, new), encoding='utf-8')
    print(f'patched: {path}')

patch(
    'rt76-master-plan.js',
    "document.title=document.title.replace(/RT77[^|—]*/,'RT78 Estratégia Completa');",
    "const legacyTitle=document.title.replace(/RT77[^|—]*/,'RT78 Estratégia Completa');if(legacyTitle!==document.title) document.title=legacyTitle;",
)
patch(
    'rt76-master-plan.js',
    "const observer=new MutationObserver(()=>queueMicrotask(ensure));observer.observe(document.documentElement,{childList:true,subtree:true});",
    "let ensurePending=false;const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure()},90)};const observer=new MutationObserver(scheduleEnsure);observer.observe(document.body||document.documentElement,{childList:true,subtree:true});",
)
patch(
    'rt76-master-plan.js',
    ";(()=>{if(window.__RT78_ADMIN_LOADER__)return;window.__RT78_ADMIN_LOADER__=true;const x=document.createElement('script');x.src='rt78-admin-suite.js?v=78.0';x.defer=true;document.head.appendChild(x)})();",
    ";(()=>{window.__RT78_ADMIN_LOADER_DISABLED_BY_RT79__=true;})();",
)
patch(
    'rt76-runtime.js',
    "new MutationObserver(()=>queueMicrotask(inject)).observe(document.getElementById('app')||document.body,{childList:true,subtree:true});setInterval(()=>{try{RT76.processScheduled(Date.now());inject()}catch(e){console.error('RT76 scheduler',e)}},1000);inject();",
    "let injectPending=false;const scheduleInject=()=>{if(injectPending)return;injectPending=true;setTimeout(()=>{injectPending=false;inject()},90)};new MutationObserver(scheduleInject).observe(document.getElementById('app')||document.body,{childList:true,subtree:true});setInterval(()=>{try{RT76.processScheduled(Date.now());inject()}catch(e){console.error('RT76 scheduler',e)}},1000);inject();",
)
patch(
    'rt76-map-ai.js',
    "new MutationObserver(()=>queueMicrotask(inject)).observe(document.getElementById('app')||document.body,{childList:true,subtree:true});inject();",
    "let injectPending=false;const scheduleInject=()=>{if(injectPending)return;injectPending=true;setTimeout(()=>{injectPending=false;inject()},90)};new MutationObserver(scheduleInject).observe(document.getElementById('app')||document.body,{childList:true,subtree:true});inject();",
)

master = Path('rt76-master-plan.js').read_text(encoding='utf-8')
runtime = Path('rt76-runtime.js').read_text(encoding='utf-8')
map_ai = Path('rt76-map-ai.js').read_text(encoding='utf-8')
assert "if(legacyTitle!==document.title) document.title=legacyTitle;" in master
assert "new MutationObserver(scheduleEnsure)" in master
assert "__RT78_ADMIN_LOADER_DISABLED_BY_RT79__" in master
assert "queueMicrotask(ensure)" not in master
assert "new MutationObserver(scheduleInject)" in runtime
assert "new MutationObserver(scheduleInject)" in map_ai
print('RT79.1 legacy startup-loop hotfix applied and verified')
