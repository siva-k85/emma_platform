# EMMA Platform (Backend + Flutter Client)

This repo contains:
- Backend Cloud Functions (schedule matching, reviews, admin utilities), with helper scripts and Firestore metadata.
- A Flutter 3.x client app (Material 3, Riverpod, go_router) for Resident/Attending/Admin flows, wired to Firebase Auth, Firestore, Cloud Functions, and FCM.

## Structure
- Backend
  - `functions/shiftadmin.js` – ShiftAdmin API integration wrapper
  - `functions/shiftMatcher.js` – Matching engine (attending ↔ resident)
  - `functions/index.js` – Cloud Functions exports (API callable + schedulers + notifications)
  - `firestore.rules` / `firestore.indexes.json` – Security rules and indexes
  - `scripts/` – Project automation and verification
- Flutter client
  - `flutter_client/emma_app/` – Flutter app root
    - `lib/`
      - `app.dart` – `MaterialApp.router` with theme + router
      - `firebase_options_web.dart` – Web `FirebaseOptions` + VAPID key
      - `routing/` – `go_router` declarative routes, role redirects
      - `theme/` – design tokens + Material 3 theme
      - `core/` – auth gate, providers, guards, shimmers, errors
      - `data/` – minimal models + Firestore repos with converters
      - `features/` – auth, home shells, metrics, evaluations, admin, profile
    - `web/firebase-messaging-sw.js` – FCM service worker for web

## Required Environment Variables
Set these via `firebase functions:config:set` or a secrets manager.

| Variable | Description |
| -------- | ----------- |
| SHIFTADMIN_BASE_URL | ShiftAdmin API endpoint (scheduled shifts) |
| SHIFTADMIN_API_KEY | ShiftAdmin validation key |
| MEDRES_JUNIOR_ICS_URL | Public/accessible ICS URL for junior residents |
| MEDRES_SENIOR_ICS_URL | ICS URL for senior residents |

Example (.env for local emulator):
```
SHIFTADMIN_BASE_URL=https://www.shiftadmin.com/api_get_scheduled_shifts.php
SHIFTADMIN_API_KEY=YOUR_KEY
MEDRES_JUNIOR_ICS_URL=https://example.com/medres-junior.ics
MEDRES_SENIOR_ICS_URL=https://example.com/medres-senior.ics
```

## Firebase Project Setup
Generate `.env.local` (or refresh it after any change in Firebase Console) and a canonical project metadata file:

```
./scripts/fetch_firebase_web_config.sh
```

Outputs:
- `.env.local` – public web config + VAPID key for local development/front-end frameworks
- `config/firebase.project.json` – snapshot of Firebase web config, FCM metadata, and Firestore indexes

Ensure you are authenticated with the Firebase CLI and have access to the `emma---version-1-reboot` project before running the script.

## Verification (Automation)
Confirm `.env.local`, `config/firebase.project.json`, and the live Firebase project stay aligned:

```
node scripts/verify_firebase_setup.mjs
```

This checks:
- Web app config (API key, app ID, measurement ID, storage bucket)
- `.env.local` values
- Firestore indexes
- `firestore.rules` content vs. the recorded snapshot

## Schedule Backfill (optional)
Run after deploying the updated Cloud Functions to retrofit historical schedule documents with the new snake_case schema and evaluation blocks:

```
./scripts/backfill_schedule_schema.mjs --project emma---version-1-reboot --force
```

Options:
- `--dry-run` to preview changes
- `--batch-size` to tune processing windows (default 400)

Authenticate with `gcloud auth application-default login` or provide a service account JSON via `GOOGLE_APPLICATION_CREDENTIALS` before running.

See `docs/firestore-schema.md` for the expected post-backfill shape.

## Flutter Client

Prereqs
- Flutter 3.35.x (stable), Dart 3.9.x
- Firebase CLI (for scripts)

Initialize and run
- Web (Chrome):
  - `cd flutter_client/emma_app`
  - `flutter pub get`
  - `flutter run -d chrome`
- iOS/Android/macOS:
  - Add `google-services.json` and `GoogleService-Info.plist` to native folders (see `.gitignore` paths).
  - `flutter run`

Firebase init
- Web uses `lib/firebase_options_web.dart` (populated from `.env.local` values).
- Native uses platform config files while preserving a web code path for `kIsWeb`.
- Firestore offline persistence is enabled. FCM token is requested; web uses VAPID.
- Web Push service worker: `web/firebase-messaging-sw.js` (loaded automatically by Flutter web when hosted at `/`).

Routing and roles
- go_router with declarative routes and redirects based on `/users/{uid}.role`.
- Routes:
  - `/auth` – Login/Signup tabs
  - `/home/resident/(metrics|home|profile)` – bottom nav (Metrics default)
  - `/home/attending/(metrics|home|profile)` – bottom nav (Pending Reviews on Home)
  - `/admin` – Admin tabs (Users, Schedules, Reviews, Blocks, Topics)
  - `/evaluation/:scheduleId` – Shared evaluation form (self vs attending modes)

Design system
- Material 3 with teal primary (`#12C2B8`), light gray surfaces, rounded 24dp cards, pill buttons.
- Custom shimmer for skeletons across metric cards and profile chip.

Data layer (Firestore)
- Repos created with typed converters where applicable (Schedules, Users, ResidentMetrics, Evaluations, Topics, block_time).
- Reads minimize cost by deferring heavy aggregations to `ResidentMetrics` where present.

Implemented features
- Auth: Login/Signup (role + PGY for residents), error states, forgot password.
- Role routing: Resident/Attending/Admin homes with guarded routes.
- Resident Home: Upcoming and Past shifts lists with status and conflict badge.
- Attending Home: Pending Reviews list with CTA to evaluate.
- Evaluation Form: Likert rubric per Topic/Subtopic, auto-save draft, submit to Schedule fields, read-only when the other side is complete.
- Metrics: Pages scaffolded with shimmers; block multi-select filter wired via providers.
- Admin: Mobile-friendly tabs with Users/Schedules/Blocks/Topics listings (Reviews shows placeholder until approval API is wired).

Next milestones
- Wire Resident Metrics computations to `ResidentMetrics`+Schedules/Evaluations with block filters.
- Topic Metrics detail with averages and relevant comments in range.
- Admin Reviews: integrate approval API/Functions, bulk approve.
- Persist block selections and small cached blobs via `shared_preferences`.
- Replace fallback metrics math with denormalized reads for performance.

## Install & Run
From the `functions` directory:
```
npm install
```

Dry-run test (requires env vars):
```
node test_shift_matching.js 2025-06-08 2025-06-09
```

## Deployment
Ensure Firebase project initialized at repo root with `firebase.json` referencing this `functions` folder or deploy from inside the folder if configured.

Deploy Firestore security rules once you are confident they reflect the desired access policy:
```
firebase deploy --only firestore:rules
```
```
firebase deploy --only functions
```

## Notes & Testing
- Firestore rules are included; deploy them with `firebase deploy --only firestore:rules`.
- Flutter tests: `cd flutter_client/emma_app && flutter test` (basic smoke test included).
- Lint/analyze: `flutter analyze`.

If your live data model differs from examples in code, repositories are defensive and will not crash; adjust converters to your exact field names as needed.
