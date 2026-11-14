# TaskPet 🐣

A gamified daily-task app for personal use: your creature (🥚 → 🐣 → 🐥 → 🦅 → 🐉)
can ONLY grow when you complete ALL your daily tasks. Miss a day → energy drops
25 points and your streak resets. No pay-to-skip, no make-up mode.

## How to get the APK on your phone (no PC tools needed)

1. Create a free GitHub account, then a new **private** repository (e.g. `taskpet`).
2. Upload all these files into it (keep the folder structure).
3. Open the repo's **Actions** tab → "Build APK" → **Run workflow**.
4. Wait ~5 min, then open the completed run → **Artifacts** → download `taskpet-apk`.
5. Send the APK to your phone (Drive, email, USB) and install it.
   Android will ask you to allow "install from unknown sources" — allow it once.

## Before you build — one edit

Open `lib/main.dart` and change:

```dart
const String localTimezone = 'Asia/Dhaka';
```

to your timezone (e.g. `'Europe/London'`, `'America/New_York'`). This controls
when the 9 AM / 9 PM reminders fire.

## Privacy

Everything is stored **on your device only** (shared_preferences). No account,
no server, no analytics.

## Roadmap to Play Store (later)

- `flutter build appbundle` → `.aab` file
- Google Play Developer account ($25 one-time)
- Generate a proper upload signing key (the GitHub Actions APK is debug-signed —
  fine for personal use, NOT accepted by Play)
- Closed testing (12–20 testers, 14 days) → production
- Add a privacy policy (on-device storage makes this easy)
