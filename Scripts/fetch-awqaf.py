#!/usr/bin/env python3
"""Download official UAE Awqaf prayer times into the bundled data folder.

Usage: Scripts/fetch-awqaf.py 2027 [2028 ...]

Writes Iqama/prayer_times/<year>/<emirate>/month_NN.json in the same format the app
decodes (PrayerTimesMonthData). Awqaf publishes by Hijri year, so the newest Gregorian
year is often partial: months without data are skipped, and the last month can be short.
Run it again when Awqaf publishes more days, then rebuild the app.
"""
import json
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

API = "https://mobileappapi.awqaf.gov.ae/APIS/v3"
OUT = Path(__file__).resolve().parent.parent / "Iqama" / "prayer_times"

# Emirate slug (matches Emirate.swift) -> Awqaf areaID of the emirate capital.
AREAS = {
    "abudhabi": 1,
    "dubai": 32,
    "sharjah": 33,
    "ajman": 41,
    "ummalquwain": 44,
    "rasalkhaimah": 45,
    "fujairah": 52,
}

# The API firewall rejects requests that don't look like they come from awqaf.gov.ae.
BROWSER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                  "(KHTML, like Gecko) Version/18.0 Safari/605.1.15",
    "Origin": "https://www.awqaf.gov.ae",
    "Referer": "https://www.awqaf.gov.ae/",
    "Accept": "application/json, text/plain, */*",
}


def request_json(url, method="GET", body=None, headers=None):
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={**BROWSER_HEADERS, **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def access_token():
    data = request_json(f"{API}/sso/StartRequest?lang=en", method="POST", body=b"{}",
                        headers={"Content-Type": "application/json"})
    if not data.get("isSuccess"):
        sys.exit(f"Awqaf token request failed: {data}")
    return data["clientAccessToken"]


def fetch_year(token, year):
    url = f"{API}/prayer-time/prayertimes/{year}-01-01/{year}-12-31"
    return request_json(url, headers={"Authorization": f"Bearer {token}"})


def write_year(year, data):
    rows = defaultdict(list)  # (slug, month) -> days
    slug_for_area = {area: slug for slug, area in AREAS.items()}
    for day in data.get("prayerData", []):
        slug = slug_for_area.get(day["areaID"])
        if slug:
            rows[(slug, int(day["gDate"][5:7]))].append(day)

    if not rows:
        print(f"{year}: Awqaf has no data yet")
        return

    for (slug, month), days in sorted(rows.items()):
        days.sort(key=lambda d: d["gDate"])
        path = OUT / str(year) / slug / f"month_{month:02d}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"downloadLink": "", "azanSettings": data["azanSettings"], "prayerData": days}
        path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
                        encoding="utf-8")

    last = max(d["gDate"][:10] for days in rows.values() for d in days)
    months = sorted({m for _, m in rows})
    print(f"{year}: months {months[0]}-{months[-1]} for {len(AREAS)} emirates, last day {last}")


def main():
    years = [int(a) for a in sys.argv[1:]]
    if not years:
        sys.exit(__doc__)
    token = access_token()
    for year in years:
        write_year(year, fetch_year(token, year))


if __name__ == "__main__":
    main()
