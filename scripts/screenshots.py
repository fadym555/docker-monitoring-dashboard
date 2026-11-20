"""Capture dashboard screenshots with a headless browser (used by CI)."""
import pathlib
import sys

from playwright.sync_api import sync_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://localhost"
OUT = pathlib.Path("docs/screenshots")
URL = f"{BASE}/d/docker-monitoring/?orgId=1&from=now-15m&to=now&kiosk"

SHOTS = [
    ("overview.png", 1600, 900),
    ("full-dashboard.png", 1600, 2050),
]

OUT.mkdir(parents=True, exist_ok=True)
with sync_playwright() as p:
    browser = p.chromium.launch()
    for name, width, height in SHOTS:
        page = browser.new_page(
            viewport={"width": width, "height": height},
            ignore_https_errors=True,
        )
        page.goto(URL, wait_until="networkidle")
        page.wait_for_timeout(15_000)  # let every panel finish rendering
        page.screenshot(path=str(OUT / name))
        page.close()
        print(f"saved {OUT / name}")
    browser.close()
