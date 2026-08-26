import json
import time
from selenium.webdriver.support.ui import WebDriverWait
import rt79_edge_public_regression as edge

_original_mobile_gameplay_e2e = edge.mobile_gameplay_e2e


def capture_mobile_nav_diagnostic(driver):
    data = edge.r.js(driver, """
      const snap=(e)=>{
        if(!e)return null;
        const c=getComputedStyle(e),b=e.getBoundingClientRect();
        return {
          tag:e.tagName,class:e.className||'',view:e.dataset?.view||'',text:(e.textContent||'').trim().slice(0,80),
          display:c.display,visibility:c.visibility,opacity:c.opacity,position:c.position,overflowX:c.overflowX,overflowY:c.overflowY,
          x:b.x,y:b.y,w:b.width,h:b.height,right:b.right,bottom:b.bottom,
          parent:e.parentElement?.className||''
        };
      };
      const all=[...document.querySelectorAll('[data-view]')];
      const over=[...document.querySelectorAll('[data-view="overview"]')];
      const navs=[...document.querySelectorAll('.rt68-game-nav')];
      const scrolls=[...document.querySelectorAll('.rt68-game-nav-scroll')];
      return {
        viewport:{w:innerWidth,h:innerHeight,sw:document.documentElement.scrollWidth,sh:document.documentElement.scrollHeight},
        bodyClass:document.body.className,
        gameShell:snap(document.querySelector('.game-shell')),
        navCount:navs.length,navs:navs.map(snap),scrolls:scrolls.map(snap),
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
    print('RT80_MOBILE_NAV_DIAGNOSTIC='+json.dumps(data,ensure_ascii=False,separators=(',',':')))
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
