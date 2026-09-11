#!/usr/bin/env bash
set -e
git clone https://github.com/flutter/flutter.git -b stable --depth 1 /tmp/flutter
export PATH="/tmp/flutter/bin:$PATH"
flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=BACKEND_URL=https://jakroute-api-production.up.railway.app \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=MAPID_STYLE_URL="$MAPID_STYLE_URL"
