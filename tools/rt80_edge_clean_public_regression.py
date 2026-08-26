import time
from selenium.webdriver.support.ui import WebDriverWait
import rt79_edge_public_regression as edge

_original_mobile_gameplay_e2e = edge.mobile_gameplay_e2e


def clean_mobile_gameplay_e2e(driver):
    # online_mock() intentionally replaces window.fetch/CLOUD and leaves the RT79 overlay open.
    # The real mobile E2E must start from a fresh page so it tests the production UI, not mock state.
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
    return _original_mobile_gameplay_e2e(driver)


edge.mobile_gameplay_e2e = clean_mobile_gameplay_e2e

if __name__ == '__main__':
    edge.main()
