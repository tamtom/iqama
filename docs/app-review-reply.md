Hello App Review,

Thank you for the review. Here is the information for Prayer Times: Iqama 1.5.1 (build 17).

1. Screen recording (attached)
- Recorded on a physical iPhone with the latest iOS, from the app launch after a fresh install.
- It shows: the first-launch setup (location and notification permissions), the home screen with the countdown and the prayer times, Settings (location, Adhan voice preview, iqama offsets, Ramadan fasting mode), and the Home Screen widget.
- iOS does not record system permission alerts, so the screen only dims while each alert is open.
- "Time preview" at the end is a test tool that only TestFlight and App Review builds show. It moves the clock so that a tester can see the iqama countdown without a wait. App Store builds do not show it.
- The app has no account, no login, no user-generated content, and no in-app purchases.

2. Purpose and audience
Iqama is a prayer times app for Muslims. It shows the five daily prayer times, plays the Adhan at each prayer, and counts down to the iqama (the start of the prayer in the mosque). This helps the user get to the mosque or pray on time. In Ramadan it also shows the suhoor and iftar times. The main audience is the UAE, but the app works in all countries.

3. How to use the main features (no login necessary)
- First launch: allow the location or choose a city. Then a short Prayer Check-in introduction shows.
- Home screen: the countdown to the next Adhan or iqama, and the prayer times of the day.
- Settings > Adhan: choose a voice, tap Play, and turn the Adhan on or off for each prayer.
- Settings > Iqama times: set the minutes between the Adhan and the iqama for each prayer and for Friday.
- Settings > Ramadan > Fasting mode: the suhoor and iftar countdown.
- Widget: add it from the Home Screen widget gallery.
- Live Activity: it starts at each Adhan and ends at the iqama.
- Notifications: an alert at each Adhan, a reminder before the iqama, and, with Prayer Check-in on, a "Did you pray?" check after the iqama.

4. External services
- UAE: the official Awqaf (General Authority of Islamic Affairs and Endowments) timetables, included in the app. The app does not download them.
- Outside the UAE: the Aladhan API (api.aladhan.com). The app sends an approximate location (kilometer accuracy) or a city name. No account or key is necessary.
- Apple frameworks: Core Location, CLGeocoder, User Notifications, WidgetKit, and ActivityKit.
- No authentication, payment, analytics, advertising, or AI services.

5. Regional differences
In the UAE, the app uses the official Awqaf prayer times and iqama times. In other countries, it uses the Aladhan calculation, and the user sets the iqama times. All other features are the same. The app is not available in China.

6. Regulated industry
Not applicable. The app needs no documentation or credentials.

Best regards,
Omar Altamimi
