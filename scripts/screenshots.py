"""Capture dashboard screenshots with a headless browser (used by CI).

Also acts as a UI test: fails if the dashboard does not render through the
public HTTPS endpoint, and prints any failed requests or browser errors.
"""
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
problems = []

with sync_playwright() as p:
    browser = p.chromium.launch()
    for name, width, height in SHOTS:
        page = browser.new_page(
            viewport={"width": width, "height": height},
            ignore_https_errors=True,
            # CI runners report "en-US@posix", which Grafana cannot parse.
            locale="en-US",
            timezone_id="UTC",
        )
        page.set_default_timeout(60_000)
        page.on("requestfailed", lambda r: problems.append(f"request failed: {r.url} {r.failure}"))
        page.on("response", lambda r: r.status >= 400 and problems.append(f"HTTP {r.status}: {r.url}"))
        page.on("console", lambda m: m.type == "error" and problems.append(f"console: {m.text}"))
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))

        print(f"[{name}] opening dashboard", flush=True)
        page.goto(URL, wait_until="domcontentloaded")
        try:
            # The first row title only exists once the dashboard has rendered.
            page.get_by_text("Executive overview").first.wait_for()
            print(f"[{name}] dashboard rendered", flush=True)
        except Exception:
            page.screenshot(path=str(OUT / f"FAILED-{name}"))
            print("Dashboard did not render. Problems seen:", flush=True)
            for line in dict.fromkeys(problems):
                print("  ", line)
            sys.exit(1)

        page.wait_for_timeout(10_000)  # let every panel finish drawing
        page.screenshot(path=str(OUT / name), timeout=60_000)
        page.close()
        print(f"saved {OUT / name}")
    browser.close()

for line in dict.fromkeys(problems):
    print("note:", line)
