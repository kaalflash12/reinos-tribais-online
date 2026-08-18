from pathlib import Path

root=Path('.')

def replace(path, old, new):
    p=root/path
    s=p.read_text(encoding='utf-8')
    if old not in s:
        raise SystemExit(f'pattern not found in {path}: {old[:80]}')
    p.write_text(s.replace(old,new),encoding='utf-8')

p=root/'rt79-suite.js'
s=p.read_text(encoding='utf-8')
s=s.replace("const VERSION='79.0';","const VERSION='79.1';")
s=s.replace("    document.title=document.title.replace(/RT78[^|—]*/,'RT79 Completo');", "    const nextTitle=document.title.replace(/RT78[^|—]*/,'RT79.1 Revisado');\n    if(nextTitle!==document.title) document.title=nextTitle;")
s=s.replace("  new MutationObserver(()=>queueMicrotask(ensure)).observe(document.documentElement,{childList:true,subtree:true});\n  setInterval(()=>{ensure();if(state.open&&online()&&Date.now()-state.last>30000)refresh(true).catch(()=>{})},5000);", "  let ensurePending=false;\n  const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure()},60)};\n  new MutationObserver(scheduleEnsure).observe(document.body||document.documentElement,{childList:true,subtree:true});\n  setInterval(()=>{ensure();if(state.open&&online()&&Date.now()-state.last>30000)refresh(true).catch(()=>{})},5000);")
p.write_text(s,encoding='utf-8')

p=root/'rt79-village-ui.js'
s=p.read_text(encoding='utf-8')
s=s.replace("    badge.textContent='RT79.1 • ALDEIA VIVA • 19 EDIFÍCIOS';", "    const badgeText='RT79.1 • ALDEIA VIVA • 19 EDIFÍCIOS';\n    if(badge.textContent!==badgeText) badge.textContent=badgeText;")
s=s.replace("  new MutationObserver(()=>queueMicrotask(ensure)).observe(document.documentElement,{childList:true,subtree:true});setInterval(ensure,1800);ensure();", "  let ensurePending=false;const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure()},80)};\n  new MutationObserver(scheduleEnsure).observe(document.body||document.documentElement,{childList:true,subtree:true});setInterval(ensure,1800);ensure();")
p.write_text(s,encoding='utf-8')

replace('rt79-groups-addon.js',
"const css=document.createElement('style');css.textContent='.rt79-group-row{display:grid;grid-template-columns:140px 1fr 1fr auto;gap:8px;align-items:center;padding:7px 0;border-bottom:1px solid #343021}@media(max-width:800px){.rt79-group-row{grid-template-columns:1fr}}';document.head.appendChild(css);new MutationObserver(()=>queueMicrotask(()=>ensure().catch(()=>{}))).observe(document.documentElement,{childList:true,subtree:true});setInterval(()=>ensure().catch(()=>{}),2500)",
"const css=document.createElement('style');css.textContent='.rt79-group-row{display:grid;grid-template-columns:140px 1fr 1fr auto;gap:8px;align-items:center;padding:7px 0;border-bottom:1px solid #343021}@media(max-width:800px){.rt79-group-row{grid-template-columns:1fr}}';document.head.appendChild(css);let ensurePending=false;const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure().catch(()=>{})},100)};new MutationObserver(scheduleEnsure).observe(document.body||document.documentElement,{childList:true,subtree:true});setInterval(()=>ensure().catch(()=>{}),2500)")

replace('rt79-logistics-ai-addon.js',
"new MutationObserver(()=>queueMicrotask(()=>ensure().catch(()=>{}))).observe(document.documentElement,{childList:true,subtree:true});setInterval(()=>ensure().catch(()=>{}),2200);",
"let ensurePending=false;const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure().catch(()=>{})},100)};new MutationObserver(scheduleEnsure).observe(document.body||document.documentElement,{childList:true,subtree:true});setInterval(()=>ensure().catch(()=>{}),2200);")

replace('rt79-admin-suite.js',
"new MutationObserver(()=>queueMicrotask(ensure)).observe(document.documentElement,{childList:true,subtree:true});ensure();",
"let ensurePending=false;const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure()},100)};new MutationObserver(scheduleEnsure).observe(document.body||document.documentElement,{childList:true,subtree:true});ensure();")

replace('rt79-admin-logistics-addon.js',
"new MutationObserver(()=>queueMicrotask(ensure)).observe(document.documentElement,{childList:true,subtree:true});ensure();",
"let ensurePending=false;const scheduleEnsure=()=>{if(ensurePending)return;ensurePending=true;setTimeout(()=>{ensurePending=false;ensure()},100)};new MutationObserver(scheduleEnsure).observe(document.body||document.documentElement,{childList:true,subtree:true});ensure();")

suite=(root/'rt79-suite.js').read_text(encoding='utf-8')
village=(root/'rt79-village-ui.js').read_text(encoding='utf-8')
assert "const VERSION='79.1';" in suite
assert "if(nextTitle!==document.title) document.title=nextTitle;" in suite
assert "new MutationObserver(scheduleEnsure)" in suite
assert "if(badge.textContent!==badgeText)" in village
print('RT79.1 observer-loop hotfix applied')
