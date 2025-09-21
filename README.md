# EMMA Platform (Rebuild Skeleton)

This directory contains a fresh implementation scaffold of the EMMA platform backend Cloud Functions (Shift Matching + Notifications) per the provided specification, plus Firebase project automation to keep the web configuration, env files, and Firestore metadata in sync.

## Structure
- `functions/shiftadmin.js` – ShiftAdmin API integration wrapper
- `functions/medres.js` – MedRes ICS parser (junior/senior resident schedules)
- `functions/shiftMatcher.js` – Matching engine (attending ↔ resident)
- `functions/index.js` – Cloud Functions exports (API callable + schedulers + notifications)
- `functions/test_shift_matching.js` – Ad-hoc dry-run tester

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

## Verification
Confirm `.env.local`, `config/firebase.project.json`, and the live Firebase project stay aligned:

```
node scripts/verify_firebase_setup.mjs
```

This checks:
- Web app config (API key, app ID, measurement ID, storage bucket)
- `.env.local` values
- Firestore indexes
- `firestore.rules` content vs. the recorded snapshot

## Schedule Backfill
Run after deploying the updated Cloud Functions to retrofit historical schedule documents with the new snake_case schema and evaluation blocks:

```
./scripts/backfill_schedule_schema.mjs --project emma---version-1-reboot --force
```

Options:
- `--dry-run` to preview changes
- `--batch-size` to tune processing windows (default 400)

Authenticate with `gcloud auth application-default login` or provide a service account JSON via `GOOGLE_APPLICATION_CREDENTIALS` before running.

See `docs/firestore-schema.md` for the expected post-backfill shape.

## Flutter Card Queries
Implementation notes for the home evaluation cards (queries, status buckets, caching) live in `docs/flutter-home-cards.md`. Apply those patterns once the Flutter client is scaffolded to keep UI and backend in sync.

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

## TODO (Next Steps)
- Add Firestore security rules referencing new collections (`shift_matching_logs`, `evaluations`, `schedules`).
- Implement evaluation create endpoints & comparison logic service.
- Integrate authentication role enforcement helpers (wrap callable/API).
- Add rate limiting + input validation layer.
- Add automated tests with Emulator (Jest) instead of ad-hoc script.
- Flutter client implementation for evaluation forms (not included here yet).

## Notes
This is a scaffold and does not include the Flutter UI or evaluation submission functions yet. Extend by adding callable functions for creating evaluations and marking completion states accordingly.
