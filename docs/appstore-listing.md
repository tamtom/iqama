# Iqama — App Store listing (iPhone)

Draft metadata for `com.itdeveapps.iqama`. Edit anything before we push it via `asc`.

## Identity
- **App Name** (≤30): `Iqama: Prayer Times & Azan`
- **Subtitle** (≤30): `Iqama countdown & reminders`
- **Primary category:** Lifestyle
- **Secondary category:** Reference
- **Age rating:** 4+ (no objectionable content)
- **Bundle ID:** `com.itdeveapps.iqama`
- **Privacy policy URL:** _(host `docs/privacy-policy.html` and paste the URL)_
- **Support URL:** _(needed — e.g. the GitHub repo, or a contact page)_

## Promotional text (≤170, updatable anytime)
> Never miss a prayer. Iqama counts down to azan and iqama, holds you to it with a “did you pray?” check-in, and lives on your Lock Screen and home screen.

## Description (≤4000)
Iqama keeps the next prayer and iqama one glance away — a calm, accurate countdown with reminders that actually follow up.

**Accurate times, wherever you are**
• Official Awqaf prayer times bundled for every emirate in the UAE — no network needed.
• Anywhere else in the world, times are calculated for your city via the Aladhan service.
• Set your location automatically, or pick your emirate / city by hand.

**A countdown you can’t miss**
• A live countdown to the next azan, then to iqama.
• Home Screen and Lock Screen widgets with the same countdown and the day’s schedule.
• A Live Activity and Dynamic Island countdown so the next prayer is always in view.

**Prayer Check-in**
• Optional “did you pray?” follow-ups after iqama that keep gently asking until you confirm.
• Commit with “Wallah, going to pray now,” or confirm afterward — then it stands down.
• Choose which prayers to be held to, and how often it checks in.

**Thoughtful details**
• A time-of-day sky that moves with the sun and moon.
• Custom iqama offsets per prayer, including a separate Friday setting.
• Hijri date, and a clear view of today’s five prayers at a glance.

Private by design: no account, no ads, no tracking. Location is only used to find your prayer times.

## Keywords (≤100 chars, comma-separated)
`prayer times,iqama,salah,azan,adhan,namaz,muslim,islam,UAE,Dubai,athan,prayer,qibla,ramadan`

## What's New (for v1.0)
> First release on iPhone: live prayer & iqama countdown, Home/Lock Screen widgets, Dynamic Island Live Activity, and the “did you pray?” check-in.

## App Privacy (data collection answers)
- **Location (Coarse Location)** — Yes, collected.
  - Purpose: **App Functionality** (computing prayer times).
  - Linked to the user's identity: **No**.
  - Used for tracking: **No**.
- All other data types: **Not Collected** (no contact info, identifiers, analytics, diagnostics, purchases, usage data).
- Reason location leaves the device: city/coordinates are sent to the Aladhan API only to calculate prayer times outside the UAE; UAE times are bundled and need no network.

## Notes / decisions
- Minimum iOS: **26.0** (the app's Liquid Glass UI uses iOS 26 APIs).
- v1 ships **without an App Group**, so the Home Screen widget shows bundled UAE data live; non-UAE live data in the widget is a fast follow-up (needs an App Group capability). The main app and Live Activity show correct non-UAE times already.
