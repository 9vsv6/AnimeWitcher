#!/usr/bin/env bash
set -euo pipefail

plist_path="${1:-ios/Runner/Info.plist}"
ios_client_id="${ANIMEWITCHER_GOOGLE_IOS_CLIENT_ID:-}"
server_client_id="${ANIMEWITCHER_GOOGLE_SERVER_CLIENT_ID:-}"

# Email/password account builds do not require Google OAuth configuration.
if [[ -z "$ios_client_id" ]]; then
  exit 0
fi

suffix=".apps.googleusercontent.com"
if [[ "$ios_client_id" != *"$suffix" ]]; then
  echo "ANIMEWITCHER_GOOGLE_IOS_CLIENT_ID is not a valid Google OAuth iOS client ID." >&2
  exit 1
fi

client_prefix="${ios_client_id%$suffix}"
reversed_client_id="com.googleusercontent.apps.${client_prefix}"
plist_buddy="/usr/libexec/PlistBuddy"

set_string() {
  local key="$1"
  local value="$2"
  if "$plist_buddy" -c "Print :$key" "$plist_path" >/dev/null 2>&1; then
    "$plist_buddy" -c "Set :$key $value" "$plist_path"
  else
    "$plist_buddy" -c "Add :$key string $value" "$plist_path"
  fi
}

set_string "GIDClientID" "$ios_client_id"
if [[ -n "$server_client_id" ]]; then
  set_string "GIDServerClientID" "$server_client_id"
fi

if ! "$plist_buddy" -c "Print :CFBundleURLTypes" "$plist_path" >/dev/null 2>&1; then
  "$plist_buddy" -c "Add :CFBundleURLTypes array" "$plist_path"
fi

url_types="$($plist_buddy -c "Print :CFBundleURLTypes" "$plist_path")"
if ! grep -Fq "$reversed_client_id" <<<"$url_types"; then
  next_index="$(grep -c 'Dict {' <<<"$url_types" || true)"
  "$plist_buddy" -c "Add :CFBundleURLTypes:$next_index dict" "$plist_path"
  "$plist_buddy" -c "Add :CFBundleURLTypes:$next_index:CFBundleTypeRole string Editor" "$plist_path"
  "$plist_buddy" -c "Add :CFBundleURLTypes:$next_index:CFBundleURLName string AnimeWitcherGoogleSignIn" "$plist_path"
  "$plist_buddy" -c "Add :CFBundleURLTypes:$next_index:CFBundleURLSchemes array" "$plist_path"
  "$plist_buddy" -c "Add :CFBundleURLTypes:$next_index:CFBundleURLSchemes:0 string $reversed_client_id" "$plist_path"
fi
