#!/usr/bin/env bash

preferans_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

preferans_cd_repo_root() {
  cd "$(preferans_repo_root)"
}

preferans_help_from_header() {
  sed -n '2,/^set -euo/p' "$1" | sed 's/^# \{0,1\}//; /^set -euo/d'
}

preferans_destination() {
  local dest_name="$1"
  printf 'platform=iOS Simulator,name=%s' "$dest_name"
}

preferans_sim_udid_for_name() {
  local dest_name="$1"
  xcrun simctl list devices available -j \
    | /usr/bin/python3 -c "
import json, sys
name = '$dest_name'
data = json.load(sys.stdin)
for runtime, devs in data['devices'].items():
    for d in devs:
        if d.get('name') == name and d.get('isAvailable'):
            print(d['udid']); sys.exit(0)
sys.exit(1)
"
}

preferans_build_for_testing() {
  local scheme="$1"
  local dest="$2"
  local derived="$3"
  xcodebuild build-for-testing \
    -project Preferans.xcodeproj \
    -scheme "$scheme" \
    -destination "$dest" \
    -derivedDataPath "$derived" \
    -quiet
}

preferans_test_without_building() {
  local scheme="$1"
  local dest="$2"
  local derived="$3"
  shift 3
  xcodebuild test-without-building \
    -project Preferans.xcodeproj \
    -scheme "$scheme" \
    -destination "$dest" \
    -derivedDataPath "$derived" \
    "$@"
}

preferans_build_app() {
  local scheme="$1"
  local sim_udid="$2"
  local derived="$3"
  xcodebuild build \
    -project Preferans.xcodeproj \
    -scheme "$scheme" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$sim_udid" \
    -derivedDataPath "$derived" \
    -quiet
}

preferans_built_app_path() {
  local scheme="$1"
  local derived="$2"
  find "$derived/Build/Products" -type d -name "${scheme}.app" -path '*-iphonesimulator*' -print -quit
}
