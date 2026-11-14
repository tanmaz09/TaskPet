# TaskPet — Final-Stage Development Roadmap

Everything this app could need before (and after) launch, grouped by area.
v2 (current) already includes: onboarding, hand-drawn animated creature that
reacts to energy, evolution popups, confetti + haptics, streak freezes,
weekly boss, stats heatmap, backup/restore, reminder notifications.

## 1. Visual & Feel (attraction layer)
- Replace code-drawn art with real animated characters (Rive or Lottie)
  — idle animations, happy/sad states, evolution cinematics
- App icon (adaptive icon for Android), splash screen, polished color theme
- Sound design: satisfying check-off "ding", evolution fanfare, ambient loop
- Micro-animations everywhere: task check morph, progress bar fills, screen transitions
- Widget on the phone home screen: creature + today's progress at a glance
- Unlockable creature skins / color variants as long-term rewards

## 2. Game Systems (depth layer)
- Task difficulty tiers (easy/medium/hard → different energy + boss damage)
- Rest days: 1 planned "rest day" per week that doesn't break the streak
- Habits vs one-off tasks (habits recur, one-offs can be scheduled)
- Achievements/badges: 7-day streak, 30 perfect days, early bird, night owl
- Seasonal events: December boss, new-year reset rewards
- Creature naming + personality that reacts to *when* you complete tasks

## 3. ADHD-Friendly Retention (the core value)
- Smart notifications: nag at the user's actual active hours (learned pattern)
- "One-tap rescue" mode when the streak breaks: a tiny comeback quest
- Evening countdown pressure ("3 tasks left — 4h to midnight")
- Homescreen widget + lock-screen streak counter = constant ambient reminder
- Anti-shame design: after a miss, celebrate restarting instead of punishing

## 4. Social & Accountability (phase 2)
- Accountability partner: a friend sees only your streak status
- Small private groups (3–5 people) with a shared weekly boss
- Optional anonymous leaderboards by streak length

## 5. Technical / Production hardening
- Proper release signing key + Play App Signing (debug key is NOT accepted by Play)
- Build `.aab` (app bundle) instead of APK for the store
- Firebase Crashlytics for crash reports (opt-in)
- Cloud sync (Firebase) so progress survives a lost phone — with offline-first mode
- Android 13+ notification permission request flow (explain why)
- Battery-optimization exemption prompt so reminders fire reliably
- Automated tests + CI build on every push (already partially set up)
- Accessibility pass (screen reader labels, contrast, reduced motion)

## 6. Play Store Compliance & Launch
- Google Play Developer account ($25 one-time)
- Closed testing: 12–20 testers, 14 days minimum (required for new personal accounts)
- Privacy policy URL (on-device storage = simple one-pager)
- Data safety form, content rating questionnaire, ads declaration (none)
- Store listing: feature graphic, 8 screenshots, short/long description, ASO keywords
  ("ADHD todo", "gamified habits", "habit tracker with pet")
- Pre-launch report check (vitals, crashes on real devices)

## 7. Post-Launch Growth
- Respond to first reviews fast; iterate weekly for the first month
- Ask happy users for ratings at the moment of a perfect day (peak emotion)
- Optional: iOS version (same Flutter codebase, ~80% reusable)
- Monetization options that respect the "no pay-to-skip" rule:
  one-time "supporter" unlock (themes/skins), never selling progress

## ADHD Ethics Guardrail (keep this forever)
No loot boxes, no variable-ratio gambling rewards, no infinite scroll.
The urgency must come from *real consequences you earned*, not engineered
addiction loops. That's what makes this app trustworthy for the audience.
