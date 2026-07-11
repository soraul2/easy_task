#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
device_id="${EASYTASK_DEVICE_ID:-${1:-}}"
xcode_device_id="${EASYTASK_XCODE_DEVICE_ID:-${2:-$device_id}}"
derived_root="${EASYTASK_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/EasyTaskCloudKitConvergence}"
probe_timeout="${EASYTASK_PROBE_TIMEOUT:-180}"
log_root="$(mktemp -d "${TMPDIR:-/tmp}/EasyTaskCloudKitProbe.XXXXXX")"

if [[ -z "$device_id" ]]; then
  print -u2 "usage: EASYTASK_DEVICE_ID=<devicectl-id> EASYTASK_XCODE_DEVICE_ID=<xcode-udid> $0"
  exit 64
fi

mac_app="$derived_root/Build/Products/Debug/EasyTask macOS.app"
mac_binary="$mac_app/Contents/MacOS/EasyTask macOS"
ios_app="$derived_root/Build/Products/Debug-iphoneos/EasyTask.app"
bundle_id="com.soraul2.easytask"
mac_pid=""
device_session_pid=""
token_mac="$(uuidgen)"
token_ios="$(uuidgen)"

cd "$repo_root"

stop_process() {
  local pid="${1:-}"
  local attempt
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null || true
    for attempt in {1..10}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  fi
}

cleanup_processes() {
  stop_process "$mac_pid"
  stop_process "$device_session_pid"
}

best_effort_marker_cleanup() {
  local token
  local cleanup_pid

  [[ -x "$mac_binary" ]] || return 0
  print -u2 "Probe failed; removing diagnostic markers where possible."

  for token in "$token_mac" "$token_ios"; do
    NSUnbufferedIO=YES "$mac_binary" \
      --cloudkit-probe-role cleanup \
      --cloudkit-probe-token "$token" \
      >/dev/null 2>&1 &
    cleanup_pid=$!
    sleep 4
    stop_process "$cleanup_pid"

    xcrun devicectl device process launch \
      --device "$device_id" \
      --terminate-existing \
      --console \
      --timeout 20 \
      "$bundle_id" \
      --cloudkit-probe-role cleanup \
      --cloudkit-probe-token "$token" \
      >/dev/null 2>&1 &
    cleanup_pid=$!
    sleep 4
    stop_process "$cleanup_pid"
  done
}

finish() {
  local exit_code="$1"
  trap - EXIT
  cleanup_processes
  if (( exit_code != 0 )); then
    best_effort_marker_cleanup
  fi
  exit "$exit_code"
}

trap 'finish $?' EXIT
trap 'exit 130' INT TERM

wait_for_success() {
  local log_file="$1"
  local role="$2"
  local seconds="${3:-30}"
  local elapsed=0

  while (( elapsed < seconds )); do
    if grep -Fq "\"passed\":true,\"role\":\"$role\"" "$log_file" 2>/dev/null; then
      cat "$log_file"
      return 0
    fi
    if grep -Fq '"passed":false' "$log_file" 2>/dev/null; then
      cat "$log_file" >&2
      return 1
    fi
    sleep 1
    (( elapsed += 1 ))
  done

  cat "$log_file" >&2 || true
  print -u2 "CloudKit probe timed out waiting for local $role result."
  return 1
}

start_mac_probe() {
  local role="$1"
  local token="$2"
  local log_file="$3"

  NSUnbufferedIO=YES "$mac_binary" \
    --cloudkit-probe-role "$role" \
    --cloudkit-probe-token "$token" \
    >"$log_file" 2>&1 &
  mac_pid=$!
  wait_for_success "$log_file" "$role"
}

run_mac_reader() {
  local token="$1"
  local expectation="$2"

  NSUnbufferedIO=YES "$mac_binary" \
    --cloudkit-probe-role reader \
    --cloudkit-probe-token "$token" \
    --cloudkit-probe-expect "$expectation" \
    --cloudkit-probe-timeout "$probe_timeout" \
    --cloudkit-probe-exit
}

start_device_probe() {
  local role="$1"
  local token="$2"
  local log_file="$3"

  xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    --console \
    --timeout "$((probe_timeout + 60))" \
    "$bundle_id" \
    --cloudkit-probe-role "$role" \
    --cloudkit-probe-token "$token" \
    >"$log_file" 2>&1 &
  device_session_pid=$!
  wait_for_success "$log_file" "$role"
}

run_device_reader() {
  local token="$1"
  local expectation="$2"

  xcrun devicectl device process launch \
    --device "$device_id" \
    --terminate-existing \
    --console \
    --timeout "$((probe_timeout + 60))" \
    "$bundle_id" \
    --cloudkit-probe-role reader \
    --cloudkit-probe-token "$token" \
    --cloudkit-probe-expect "$expectation" \
    --cloudkit-probe-timeout "$probe_timeout" \
    --cloudkit-probe-exit
}

if [[ "${EASYTASK_SKIP_BUILD:-0}" != "1" ]]; then
  print "[1/5] Building signed macOS Debug app"
  xcodebuild -quiet \
    -project EasyTask.xcodeproj \
    -scheme EasyTask-macOS \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_root" \
    -allowProvisioningUpdates \
    build

  print "[2/5] Building signed iPhone Debug app"
  xcodebuild -quiet \
    -project EasyTask.xcodeproj \
    -scheme EasyTask-iOS \
    -configuration Debug \
    -destination "id=$xcode_device_id" \
    -derivedDataPath "$derived_root" \
    -allowProvisioningUpdates \
    build
fi

[[ -x "$mac_binary" ]] || { print -u2 "Missing macOS app: $mac_binary"; exit 66; }
[[ -d "$ios_app" ]] || { print -u2 "Missing iOS app: $ios_app"; exit 66; }

print "[3/5] Installing iPhone app"
xcrun devicectl device install app --device "$device_id" "$ios_app"
print "Probe tokens: macOS=$token_mac iPhone=$token_ios"

print "[4/5] Verifying macOS -> iPhone create and delete"
start_mac_probe writer "$token_mac" "$log_root/mac-writer.log"
run_device_reader "$token_mac" present
stop_process "$mac_pid"
mac_pid=""
start_mac_probe cleanup "$token_mac" "$log_root/mac-cleanup.log"
run_device_reader "$token_mac" absent
stop_process "$mac_pid"
mac_pid=""

print "[5/5] Verifying iPhone -> macOS create and delete"
start_device_probe writer "$token_ios" "$log_root/ios-writer.log"
run_mac_reader "$token_ios" present
stop_process "$device_session_pid"
device_session_pid=""
start_device_probe cleanup "$token_ios" "$log_root/ios-cleanup.log"
run_mac_reader "$token_ios" absent
stop_process "$device_session_pid"
device_session_pid=""

print "CloudKit convergence probe passed in both directions."
print "Logs: $log_root"
