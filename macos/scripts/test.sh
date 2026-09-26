#!/bin/bash
# The Mac app's tests (SWIFTUI_REBUILD.md section 8), run from anywhere:
#
#   macos/scripts/test.sh
#
#   1. writes the synthetic league into a scratch folder (npm run synthetic:league), never a real save;
#   2. stages the server for the bundle (npm run mac:stage);
#   3. runs each package's Swift tests (PennantAPI, PennantKit and PennantFeatures with their real-server integration
#      tests, PennantDesign); PennantFeatures also draws the shell's snapshots into build/macos-snapshots/;
#   4. runs `xcodebuild test` on the Pennant scheme: the app with its server and the XCUITests, each test on a fresh
#      scratch data folder holding the synthetic league;
#   5. extracts the XCUITest screenshots with xcresulttool.
#
# Output goes to build/macos-test/ (ignored by Git): logs/, Pennant.xcresult and screenshots/. Only summaries and
# failures are printed.
#
# Environment:
#   PENNANT_TEST_SCRATCH   the scratch folder (default: a new folder under $TMPDIR)
#   PENNANT_TEST_UNSIGNED  1 builds without signing (CODE_SIGNING_ALLOWED=NO)
#   PENNANT_TEST_NO_UI     1 skips step 4 and 5 (the package tests still run)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/macos-test"
LOGS="$OUT/logs"
SCRATCH="${PENNANT_TEST_SCRATCH:-$(mktemp -d "${TMPDIR:-/tmp}/pennant-macos-test.XXXXXX")}"
mkdir -p "$LOGS" "$SCRATCH"
LEAGUE="$SCRATCH/league/league.db"
failed=0

step() { echo; echo "== $*"; }

# Runs a command with its output in a log; prints the summary lines, and the failures if it failed
run() {
  local name="$1" summary="$2"
  shift 2
  local log="$LOGS/$name.log"
  if "$@" >"$log" 2>&1; then
    grep -E "$summary" "$log" | tail -3 || true
  else
    echo "FAILED: $name (full log: $log)"
    grep -E "error:|✘|FAIL|failed|Failing tests|\*\* TEST|\*\* BUILD" "$log" | grep -v GeneratedSources | head -40 || tail -30 "$log"
    return 1
  fi
}

cd "$ROOT"
step "Synthetic league in $SCRATCH/league"
run synthetic-league "synthetic-league" npm run synthetic:league -- "$SCRATCH/league" || failed=1

step "Staging the server (npm run mac:stage)"
run stage "\[stage\] staged" npm run mac:stage || failed=1

for package in PennantAPI PennantKit PennantDesign PennantFeatures; do
  step "swift test: $package"
  (cd "$ROOT/macos/Packages/$package" && \
    run "swift-test-$package" "Test run with|Executed" \
      env PENNANT_TEST_SCRATCH="$SCRATCH/swift" PENNANT_TEST_LEAGUE="$LEAGUE" swift test) || failed=1
done

if [ "${PENNANT_TEST_NO_UI:-0}" != "1" ]; then
  step "xcodebuild test: the Pennant scheme (app, server, XCUITests)"
  UI_SCRATCH="$SCRATCH/ui"
  rm -rf "$UI_SCRATCH" "$OUT/Pennant.xcresult" "$OUT/screenshots"
  mkdir -p "$UI_SCRATCH"
  signing=()
  if [ "${PENNANT_TEST_UNSIGNED:-0}" = "1" ]; then signing=(CODE_SIGNING_ALLOWED=NO); fi
  # TEST_RUNNER_ variables reach the test runner without the prefix: each UI test copies the league into a data
  # folder of its own under the scratch folder and launches the app on it
  run xcodebuild-test "Executed|\*\* TEST" \
    env TEST_RUNNER_PENNANT_UI_SCRATCH="$UI_SCRATCH" TEST_RUNNER_PENNANT_UI_LEAGUE="$LEAGUE" \
    xcodebuild -project "$ROOT/macos/Pennant.xcodeproj" -scheme Pennant -destination 'platform=macOS' \
      -derivedDataPath "$OUT/DerivedData" -resultBundlePath "$OUT/Pennant.xcresult" \
      -skipPackagePluginValidation ${signing[@]+"${signing[@]}"} test || failed=1
  if grep -q "enabling automation mode" "$LOGS/xcodebuild-test.log"; then
    echo "UI automation is not enabled on this Mac, so the XCUITests could not drive the app. Enable it once as the"
    echo "Mac's owner (it asks for your password): run the Pennant scheme's tests from Xcode, or"
    echo "  automationmodetool enable-automationmode-without-authentication"
    echo "Or skip the UI tests: PENNANT_TEST_NO_UI=1 macos/scripts/test.sh"
  fi

  if [ -d "$OUT/Pennant.xcresult" ]; then
    step "Screenshots"
    mkdir -p "$OUT/screenshots"
    if xcrun xcresulttool export attachments --path "$OUT/Pennant.xcresult" --output-path "$OUT/screenshots" \
      >"$LOGS/attachments.log" 2>&1; then
      count="$(find "$OUT/screenshots" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.heic' \) | wc -l | tr -d ' ')"
      echo "$count screenshot(s) in build/macos-test/screenshots/"
    else
      echo "Could not extract the attachments (see $LOGS/attachments.log)"
    fi
  fi
fi

if [ -d "$ROOT/build/macos-snapshots" ]; then
  echo
  echo "$(find "$ROOT/build/macos-snapshots" -name '*.png' | wc -l | tr -d ' ') snapshot(s) in build/macos-snapshots/"
fi

echo
if [ "$failed" = "0" ]; then echo "All Mac tests passed."; else echo "Some Mac tests FAILED (logs in build/macos-test/logs/)."; fi
exit "$failed"
