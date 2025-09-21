# EMMA Platform (Rebuild Skeleton)

This directory contains a fresh implementation scaffold of the EMMA platform backend Cloud Functions (Shift Matching + Notifications) per the provided specification.

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
