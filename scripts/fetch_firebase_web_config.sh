#!/usr/bin/env bash
set -euo pipefail

# Fetch Firebase Web APP_ID and MEASUREMENT_ID, then write .env.local
# and config/firebase.project.json for the EMMA project.

PROJECT_ID=${PROJECT_ID:-"emma---version-1-reboot"}
API_KEY=${FIREBASE_API_KEY:-""}
AUTH_DOMAIN=${FIREBASE_AUTH_DOMAIN:-""}
STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET:-""}
SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID:-""}
VAPID_PUBLIC_KEY=${FIREBASE_VAPID_PUBLIC_KEY:-"BLm_aFdw75KK8xTJm2Axch5G8p6YXbw21_d-nAj3BeriDFjx6OpU-JuAfYYGC2qmP58aOd8NdThL2MrDPNg2k-A"}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing '$1'. Please install it first." >&2
    exit 1
  }
}

need firebase
need jq

echo "Using project: $PROJECT_ID"

# Ensure the active project is set (non-fatal if it fails)
firebase use "$PROJECT_ID" >/dev/null 2>&1 || true

echo "Fetching Web APP_ID..."
APP_ID=${FIREBASE_APP_ID:-""}
if [[ -z "$APP_ID" ]]; then
  APP_ID=$(firebase apps:list --project "$PROJECT_ID" --json \
    | jq -r '.result[] | select(.platform=="WEB") | .appId' | head -n1)
fi

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  echo "error: No WEB app found for project '$PROJECT_ID'. Create one in Firebase Console or via CLI:" >&2
  echo "       firebase apps:create WEB \"EMMA Web\" --project $PROJECT_ID" >&2
  exit 1
fi

echo "APP_ID: $APP_ID"

echo "Fetching SDK config..."
MEASUREMENT_ID=${FIREBASE_MEASUREMENT_ID:-""}
CONFIG_JSON=$(firebase apps:sdkconfig web "$APP_ID" --project "$PROJECT_ID" --json 2>/dev/null || true)

if [[ -n "$CONFIG_JSON" ]]; then
  SDK_NODE=$(echo "$CONFIG_JSON" | jq -r '.sdkConfig // .result.sdkConfig // empty')
  if [[ -n "$SDK_NODE" ]]; then
    API_KEY=${API_KEY:-$(echo "$SDK_NODE" | jq -r '.apiKey // empty')}
    AUTH_DOMAIN=${AUTH_DOMAIN:-$(echo "$SDK_NODE" | jq -r '.authDomain // empty')}
    STORAGE_BUCKET=${STORAGE_BUCKET:-$(echo "$SDK_NODE" | jq -r '.storageBucket // empty')}
    SENDER_ID=${SENDER_ID:-$(echo "$SDK_NODE" | jq -r '.messagingSenderId // empty')}
    APP_ID=$(echo "$SDK_NODE" | jq -r '.appId // empty')
    MEASUREMENT_ID=${MEASUREMENT_ID:-$(echo "$SDK_NODE" | jq -r '.measurementId // empty')}
  fi
fi

# Fallback to plaintext parsing if needed.
if [[ -z "$MEASUREMENT_ID" ]]; then
  MEASUREMENT_ID=$(firebase apps:sdkconfig web "$APP_ID" --project "$PROJECT_ID" \
    | grep -Eo 'G-[A-Z0-9]+' | head -n1 || true)
fi

if [[ -z "$STORAGE_BUCKET" ]]; then
  STORAGE_BUCKET="${PROJECT_ID}.appspot.com"
fi

for var_name in API_KEY AUTH_DOMAIN SENDER_ID APP_ID; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "error: $var_name could not be resolved from Firebase SDK config. Set it via environment variables." >&2
    exit 1
  fi
done

mkdir -p config

echo "Writing .env.local ..."
cat > .env.local <<EOF
# Firebase public web config
FIREBASE_API_KEY=$API_KEY
FIREBASE_AUTH_DOMAIN=$AUTH_DOMAIN
FIREBASE_PROJECT_ID=$PROJECT_ID
FIREBASE_STORAGE_BUCKET=$STORAGE_BUCKET
FIREBASE_MESSAGING_SENDER_ID=$SENDER_ID
FIREBASE_APP_ID=$APP_ID
FIREBASE_MEASUREMENT_ID=${MEASUREMENT_ID:-}

# Web Push (VAPID) key used by FCM (choose an active public key)
FIREBASE_VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY
EOF

echo "Fetching Firestore composite indexes..."
INDEXES_RAW=$(firebase firestore:indexes --project "$PROJECT_ID" 2>/dev/null || echo '{"indexes": []}')
FIRESTORE_INDEXES=$(echo "$INDEXES_RAW" | jq -c '.indexes // []')

echo "Writing config/firebase.project.json ..."
cat > config/firebase.project.json <<EOF
{
  "project": {
    "name": "EMMA - Version 1 Reboot",
    "id": "$PROJECT_ID",
    "number": "365227575795",
    "environment": "Production"
  },
  "webConfig": {
    "apiKey": "$API_KEY",
    "authDomain": "$AUTH_DOMAIN",
    "projectId": "$PROJECT_ID",
    "storageBucket": "$STORAGE_BUCKET",
    "messagingSenderId": "$SENDER_ID",
    "appId": "$APP_ID",
    "measurementId": "${MEASUREMENT_ID:-}"
  },
  "fcm": {
    "apiVersion": "v1",
    "enabled": true,
    "senderId": "$SENDER_ID",
    "webPush": {
      "vapidKeys": [
        {
          "publicKey": "BLm_aFdw75KK8xTJm2Axch5G8p6YXbw21_d-nAj3BeriDFjx6OpU-JuAfYYGC2qmP58aOd8NdThL2MrDPNg2k-A",
          "dateAdded": "2025-07-21",
          "status": "unknown"
        },
        {
          "publicKey": "BOi1_5mHF6KkGOPqX_TusaiUyOHBXgXJyfM-jHfTDIxDF1zFpZ6BoZ11RB-hurIHztI5hSqRdvjUPXsdCqvEHSg",
          "dateAdded": "2025-07-21",
          "status": "unknown"
        }
      ]
    }
  },
  "adminSdk": {
    "serviceAccountEmail": "firebase-adminsdk-fbsvc@emma---version-1-reboot.iam.gserviceaccount.com"
  },
  "firestore": {
    "rules": {
      "text": "rules_version = '2';\nservice cloud.firestore {\n  match /databases/{database}/documents {\n    match /{document=**} {\n      allow read, write: if false;\n    }\n  }\n}",
      "expired": false
    },
    "collections": [
      "block_time",
      "schedules",
      "topics",
      "topics_cleaned",
      "users"
    ],
    "indexes": $FIRESTORE_INDEXES
  }
}
EOF

tmpfile=$(mktemp)
jq '.' config/firebase.project.json > "$tmpfile"
mv "$tmpfile" config/firebase.project.json

echo "Done. Generated .env.local and config/firebase.project.json"
