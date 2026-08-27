import json
import time
from selenium.webdriver.support.ui import WebDriverWait
import rt79_edge_public_regression as edge

_original_mobile_gameplay_e2e = edge.mobile_gameplay_e2e

# RT80 diagnostic trigger: capture the real 390x844 DOM, nav and strategic launcher ancestry.
def capture_mobile_nav_diagnostic(driver):
    data = edge.r.js(driver, """
      const snap=(e)=>{
        if(!e)return null;
        const c=getComputedStyle(e),b=e.getBoundingClientRect();
        return {
          tag:e.tagName,class:e.className||'',id:e.id||'',view:e.dataset?.view||'',text:(e.textContent||'').trim().slice(0,80),
          display:c.display,visibility:c.visibility,opacity:c.opacity,position:c.position,overflowX:c.overflowX,overflowY:c.overflowY,
          x:b.x,y:b.y,w:b.width,h:b.height,right:b.right,bottom:b.bottom,
          parent:e.parentElement?.className||''
        };
      };
      const chain=(e)=>{const out=[];for(let n=e;n&&out.length<10;n=n.parentElement)out.push(snap(n));return out};
      const nav=document.querySelector('.rt68-game-nav');
      const launcher=document.querySelector('[data-rt79-open]');
      const applied=[];
      const walk=(rules,owner,media='')=>{
        for(const rule of [...(rules||[])]){
          try{
            if(rule.cssRules){
              const nextMedia=rule.conditionText||rule.media?.mediaText||media||'';
              walk(rule.cssRules,owner,nextMedia);
              continue;
            }
            const sel=rule.selectorText||'';
            if(!sel||!nav||!nav.matches(sel))continue;
            const style=rule.style;
            if(!style)continue;
            const interesting=['display','visibility','height','max-height','overflow','overflow-x','overflow-y','position','top','width'];
            const props={};
            for(const p of interesting){
              const v=style.getPropertyValue(p);if(v)props[p]={value:v,priority:style.getPropertyPriority(p)};
            }
            if(Object.keys(props).length)applied.push({owner,media,selector:sel,props,cssText:rule.cssText.slice(0,900)});
          }catch{}
        }
      };
      for(const sheet of [...document.styleSheets]){
        let rules=null;try{rules=sheet.cssRules}catch{}
        if(rules)walk(rules,sheet.href||sheet.ownerNode?.id||sheet.ownerNode?.tagName||'inline');
      }
      const all=[...document.querySelectorAll('[data-view]')];
      const over=[...document.querySelectorAll('[data-view="overview"]')];
      const navs=[...document.querySelectorAll('.rt68-game-nav')];
      const scrolls=[...document.querySelectorAll('.rt68-game-nav-scroll')];
      return {
        viewport:{w:innerWidth,h:innerHeight,sw:document.documentElement.scrollWidth,sh:document.documentElement.scrollHeight},
        bodyClass:document.body.className,
        gameShell:snap(document.querySelector('.game-shell')),
        navCount:navs.length,navs:navs.map(snap),scrolls:scrolls.map(snap),
        navInlineStyle:nav?.getAttribute('style')||'',navAppliedRules:applied,
        strategicLauncher:snap(launcher),strategicLauncherAncestors:chain(launcher),
        dataViewCount:all.length,overviewCount:over.length,
        overview:over.map(snap),
        firstViews:all.slice(0,30).map(snap),
        appChildren:[...document.querySelector('#app')?.children||[]].map(snap)
      };
    """)
    path=edge.r.OUT/'RT80_MOBILE_NAV_DIAGNOSTIC.json'
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    shot=edge.r.OUT/'RT80_MOBILE_NAV_DIAGNOSTIC.png'
    driver.save_screenshot(str(shot))
    print('RT80_MOBILE_NAV_DIAGNOSTIC='+json.dumps(data,ensure_ascii=True,separators=(',',':')))
    return data


def clean_mobile_gameplay_e2e(driver):
    # online_mock() intentionally replaces window.fetch/CLOUD and leaves the RT79 overlay open.
    # The real mobile E2E starts from a fresh page so it tests production UI, not mock state.
    edge.emulate_mobile(driver, 390, 844)
    edge.r.nav(driver, '?mobile-e2e=clean-entry')
    edge.emulate_mobile(driver, 390, 844)
    WebDriverWait(driver, 25).until(lambda d: edge.r.js(d, 'return !!window.__RT79_STRATEGY_SUITE__'))
    edge.r.click(driver, '[data-play-offline]')
    WebDriverWait(driver, 15).until(lambda d: edge.r.js(d, 'return !!window.RT76?.state?.()?.activeVillageId'))
    edge.r.rec(
        'mobile clean production entry',
        edge.r.js(driver, "return !!document.querySelector('.game-shell') && !document.querySelector('#rt79-overlay')?.classList.contains('open')")
    )
    capture_mobile_nav_diagnostic(driver)
    return _original_mobile_gameplay_e2e(driver)


edge.mobile_gameplay_e2e = clean_mobile_gameplay_e2e

if __name__ == '__main__':
    edge.main()
