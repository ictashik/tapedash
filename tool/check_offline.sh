#!/usr/bin/env bash
#
# Offline enforcement (CLAUDE.md 4).
#
# Fails if TapeDash could reach the network outside the WiFi transport, or pull
# in Google Play Services, Firebase or other proprietary SDKs:
#   1. pubspec.lock contains a banned package
#   2. Dart code under lib/ uses an HTTP client or a network image, or opens a
#      socket outside lib/obd/transport/wifi_transport.dart
#   3. an Android manifest requests a permission outside the allowed list
#   4. the Gradle release classpath contains a banned SDK
#   5. the navigation listener (docs/NAV.md) has network code, more than one
#      notification listener service exists, the release allowlist is not exactly
#      Google Maps, a release build adds a package or a capture tool, or a
#      notification is handed on before its package is checked
#
# Usage: tool/check_offline.sh [--strict] [--skip-gradle] [--root DIR]
#   --strict       CI mode. Requires a built release manifest and always runs the
#                  Gradle check, with no skipping.
#   --skip-gradle  Skip the Gradle check.
#   --root DIR     Check the project in DIR instead of this repository.
#
# Works with the bash 3.2 that ships with macOS.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '1d'
}

STRICT=0
SKIP_GRADLE=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --skip-gradle) SKIP_GRADLE=1 ;;
    --root)
      if [ $# -lt 2 ]; then echo "--root needs a directory" >&2; exit 2; fi
      ROOT="$(cd "$2" && pwd)"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT"

# ---- configuration ----------------------------------------------------------

# CLAUDE.md 4 bans http, dio, google_fonts, firebase_*, *_analytics, sentry* and
# any web-opening url_launcher use; url_launcher is banned outright, since the
# About page shows the project URL as text and a QR code instead. The rest are
# obviously networked or Google-account SDKs.
BANNED_PACKAGES='^(http|dio|google_fonts|url_launcher(_[a-z0-9_]+)?|firebase_[a-z0-9_]+|[a-z0-9_]+_analytics|sentry[a-z0-9_]*|cloud_firestore|cloud_functions|google_mobile_ads|google_sign_in(_[a-z0-9_]+)?|google_maps_flutter(_[a-z0-9_]+)?|webview_flutter(_[a-z0-9_]+)?|flutter_inappwebview(_[a-z0-9_]+)?|in_app_purchase(_[a-z0-9_]+)?|onesignal_flutter|mixpanel_flutter|amplitude_flutter|posthog_flutter)$'

# The only file allowed to open sockets (CLAUDE.md 4, network guard).
SOCKET_FILE='lib/obd/transport/wifi_transport.dart'

# CLAUDE.md 4. The app's own DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION, which
# androidx adds to every app, is allowed separately below.
ALLOWED_PERMISSIONS='android.permission.BLUETOOTH_CONNECT android.permission.BLUETOOTH_SCAN android.permission.BLUETOOTH android.permission.BLUETOOTH_ADMIN android.permission.ACCESS_FINE_LOCATION android.permission.WAKE_LOCK android.permission.INTERNET'

BANNED_MAVEN_GROUPS='com\.google\.android\.gms|com\.google\.firebase|com\.google\.android\.play|com\.google\.android\.libraries|com\.google\.android\.datatransport|com\.google\.mlkit|com\.crashlytics|io\.sentry'

# ---- helpers ----------------------------------------------------------------

FAILED=0
fail() { printf 'FAIL  %s\n' "$*" >&2; FAILED=1; }
ok() { printf 'ok    %s\n' "$*"; }
note() { printf 'note  %s\n' "$*"; }

hash_stdin() {
  if command -v sha256sum > /dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1
  fi
}

# ---- 1. pubspec.lock --------------------------------------------------------

check_lockfile() {
  if [ ! -f pubspec.lock ]; then
    fail "pubspec.lock is missing; run flutter pub get and commit it"
    return
  fi
  local hits name
  hits=$(sed -nE 's/^  ([a-z0-9_]+):$/\1/p' pubspec.lock | grep -E "$BANNED_PACKAGES" || true)
  if [ -n "$hits" ]; then
    while IFS= read -r name; do
      fail "pubspec.lock contains banned package '$name'"
    done <<< "$hits"
  else
    ok "pubspec.lock has no banned packages"
  fi
}

# ---- 2. Dart sources --------------------------------------------------------

# scan_dart LABEL REGEX [EXCLUDED_FILE]: report every match in lib/, ignoring
# line comments (and so documentation) and the excluded file.
scan_dart() {
  local label=$1 regex=$2 exclude=${3:-} file hits line
  while IFS= read -r file; do
    if [ -z "$file" ]; then continue; fi
    if [ -n "$exclude" ] && [ "$file" = "$exclude" ]; then continue; fi
    hits=$(sed -E 's://.*$::' "$file" | grep -nE "$regex" || true)
    if [ -n "$hits" ]; then
      while IFS= read -r line; do
        fail "$file:$line  [$label]"
      done <<< "$hits"
    fi
  done <<< "$DART_FILES"
}

check_dart() {
  DART_FILES=$(find lib -name '*.dart' -type f 2> /dev/null | sort || true)
  local before=$FAILED
  FAILED=0

  # Whole-word matching that behaves the same in BSD and GNU grep.
  local wb='(^|[^A-Za-z0-9_])' wa='($|[^A-Za-z0-9_])'

  scan_dart 'banned package import' \
    "import +['\"]package:(http|dio|google_fonts|url_launcher[a-z0-9_]*|firebase_[a-z0-9_]*|sentry[a-z0-9_]*|[a-z0-9_]+_analytics)[/'\"]"
  scan_dart 'HTTP client' "${wb}HttpClient${wa}"
  scan_dart 'network image or asset bundle' "${wb}(NetworkImage|NetworkAssetBundle|Image\.network)${wa}"
  scan_dart 'web launcher' "${wb}(launchUrl|canLaunchUrl|launchUrlString)${wa}"
  scan_dart "socket outside $SOCKET_FILE" \
    "${wb}(Socket|RawSocket|SecureSocket|RawSecureSocket|ServerSocket|RawServerSocket|RawDatagramSocket|WebSocket|HttpServer)${wa}" \
    "$SOCKET_FILE"

  if [ "$FAILED" = 0 ]; then
    ok "lib/ has no HTTP clients, network images or stray sockets"
  fi
  if [ "$before" = 1 ]; then FAILED=1; fi
}

# ---- 3. Android manifests ---------------------------------------------------

# check_manifest FILE: every requested permission must be allowed, and the
# permissions with conditions must carry them (CLAUDE.md 4).
check_manifest() {
  local file=$1 tags tag name
  local before=$FAILED
  FAILED=0

  # One tag per line, however the file is formatted. A permission removed with
  # tools:node="remove" is not a request.
  tags=$(tr '\n' ' ' < "$file" | grep -oE '<uses-permission[^>]*>' | grep -v 'tools:node="remove"' || true)
  if [ -n "$tags" ]; then
    while IFS= read -r tag; do
      name=$(printf '%s' "$tag" | sed -nE 's/.*android:name="([^"]+)".*/\1/p')
      case " $ALLOWED_PERMISSIONS " in
        *" $name "*) ;;
        *)
          if ! printf '%s' "$name" | grep -qE '^[A-Za-z0-9_.]+\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION$'; then
            fail "$file requests permission '$name', which is not on the allowed list"
          fi
          ;;
      esac
      case "$name" in
        android.permission.BLUETOOTH | android.permission.BLUETOOTH_ADMIN)
          if ! printf '%s' "$tag" | grep -qE 'android:maxSdkVersion="30"'; then
            fail "$file: $name must set android:maxSdkVersion=\"30\""
          fi
          ;;
        android.permission.BLUETOOTH_SCAN)
          if ! printf '%s' "$tag" | grep -qE 'android:usesPermissionFlags="[^"]*neverForLocation'; then
            fail "$file: $name must set android:usesPermissionFlags=\"neverForLocation\""
          fi
          ;;
      esac
    done <<< "$tags"
  fi

  if [ "$FAILED" = 0 ]; then
    ok "$file: permissions are all allowed"
  fi
  if [ "$before" = 1 ]; then FAILED=1; fi
}

check_manifests() {
  # The debug and profile manifests add INTERNET for hot reload and DevTools;
  # they are not shipped, so only the main manifest is checked at source level.
  local source=android/app/src/main/AndroidManifest.xml
  if [ -f "$source" ]; then
    check_manifest "$source"
  else
    fail "$source is missing"
  fi

  # The merged release manifest is what actually ships, permissions from
  # plugins included.
  local merged found=0
  merged=$(find build/app/intermediates -path '*merged_manifest*' -path '*release*' \
    -name AndroidManifest.xml 2> /dev/null | sort || true)
  while IFS= read -r file; do
    if [ -z "$file" ]; then continue; fi
    found=1
    check_manifest "$file"
  done <<< "$merged"
  if [ "$found" = 0 ]; then
    if [ "$STRICT" = 1 ]; then
      fail "no merged release manifest under build/; run flutter build apk --release first"
    else
      note "no merged release manifest yet (checked the source manifest only)"
    fi
  fi
}

# ---- 4. Gradle dependency tree ----------------------------------------------

gradle_inputs_hash() {
  {
    cat pubspec.lock android/gradle.properties android/gradle/wrapper/gradle-wrapper.properties 2> /dev/null || true
    find android \( -path android/build -o -path android/.gradle \) -prune -o \
      \( -name '*.gradle' -o -name '*.gradle.kts' \) -type f -print 2> /dev/null | sort |
      while IFS= read -r f; do cat "$f"; done
  } | hash_stdin
}

check_gradle() {
  if [ "$SKIP_GRADLE" = 1 ]; then
    note "Gradle dependency check skipped (--skip-gradle)"
    return
  fi

  # Nothing that changes the dependency tree has changed since the last pass.
  local stamp=build/.check_offline_gradle.stamp inputs
  inputs=$(gradle_inputs_hash)
  if [ "$STRICT" = 0 ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$inputs" ]; then
    ok "Gradle dependencies unchanged since the last passing check"
    return
  fi

  # gradlew is generated by the Flutter tool and is not committed.
  if [ ! -x android/gradlew ]; then
    if command -v flutter > /dev/null 2>&1; then
      note "generating the Gradle wrapper (flutter build apk --config-only)"
      flutter build apk --config-only > /dev/null 2>&1 || true
    fi
  fi
  if [ ! -x android/gradlew ]; then
    if [ "$STRICT" = 1 ]; then
      fail "android/gradlew is missing, so the Gradle dependency tree cannot be checked"
    else
      note "android/gradlew is missing; Gradle dependency check skipped"
    fi
    return
  fi

  local tree hits group
  if ! tree=$(cd android && ./gradlew -q :app:dependencies --configuration releaseRuntimeClasspath 2>&1); then
    fail "Gradle could not resolve the release classpath:"
    printf '%s\n' "$tree" | tail -20 >&2
    return
  fi
  # A real release classpath always contains Flutter's embedding. Without it we
  # parsed something else, and "no banned SDKs" would mean nothing.
  if ! printf '%s\n' "$tree" | grep -q 'io\.flutter:'; then
    fail "the Gradle output did not look like the release classpath:"
    printf '%s\n' "$tree" | head -20 >&2
    return
  fi
  hits=$(printf '%s\n' "$tree" | grep -oE "($BANNED_MAVEN_GROUPS)[A-Za-z0-9_.-]*:[A-Za-z0-9_.-]+" | sort -u || true)
  if [ -n "$hits" ]; then
    while IFS= read -r group; do
      fail "the release classpath contains banned dependency '$group'"
    done <<< "$hits"
    return
  fi

  ok "the release classpath has no Play Services, Firebase or other banned SDKs"
  mkdir -p build
  printf '%s\n' "$inputs" > "$stamp"
}

# ---- 5. The navigation listener ---------------------------------------------

# CLAUDE.md 4, "Navigation notification": TapeDash may read one navigation app's
# notification and nothing else, and sends nothing. With no listener there is
# nothing to check.
NAV_SRC=android/app/src
NAV_DIR=kotlin/io/github/ictashik/tapedash
MAPS_PACKAGE=com.google.android.apps.maps

# A Kotlin file's code: // comments and documentation lines (/** ... */, ` *`)
# removed, so that a word in a comment is not a use.
nav_code() { sed -E -e 's://.*$::' -e '/^[[:space:]]*(\/\*|\*)/d' "$1"; }

check_nav() {
  local service="$NAV_SRC/main/$NAV_DIR/NavListenerService.kt"
  local sources="$NAV_SRC/main/$NAV_DIR/NavSources.kt"
  if [ ! -f "$service" ]; then
    return
  fi
  local before=$FAILED
  FAILED=0

  # a. No network code in anything the navigation feature adds.
  local file hits line
  while IFS= read -r file; do
    if [ -z "$file" ]; then continue; fi
    hits=$(nav_code "$file" | grep -nE '(^|[^A-Za-z0-9_.])(java\.net|javax\.net|okhttp3?|android\.net\.(http|wifi)|org\.apache\.http)|HttpURLConnection|HttpsURLConnection|(^|[^A-Za-z0-9_])(Socket|ServerSocket|DatagramSocket|URL)\(' || true)
    if [ -n "$hits" ]; then
      while IFS= read -r line; do
        fail "$file:$line  [network code in the navigation listener]"
      done <<< "$hits"
    fi
  done <<< "$(find "$NAV_SRC" -name 'Nav*.kt' -type f 2> /dev/null | sort)"

  # b. Exactly one notification listener service, and it is ours.
  local manifest tag services count=0
  while IFS= read -r manifest; do
    if [ -z "$manifest" ]; then continue; fi
    services=$(tr '\n' ' ' < "$manifest" | grep -oE '<service[^>]*>' | grep 'BIND_NOTIFICATION_LISTENER_SERVICE' || true)
    if [ -z "$services" ]; then continue; fi
    while IFS= read -r tag; do
      count=$((count + 1))
      case "$tag" in
        *'android:name=".NavListenerService"'*) ;;
        *) fail "$manifest declares a notification listener service other than NavListenerService" ;;
      esac
    done <<< "$services"
  done <<< "$(find "$NAV_SRC" -name AndroidManifest.xml -type f 2> /dev/null | sort)"
  if [ "$count" != 1 ]; then
    fail "expected exactly one notification listener service in the manifests, found $count"
  fi

  # c. A release build looks at Google Maps and nothing else.
  local constant definition
  if [ ! -f "$sources" ]; then
    fail "$sources is missing"
  else
    constant=$(nav_code "$sources" | grep -E 'const val GOOGLE_MAPS *= *"' | head -1 | grep -oE '"[^"]*"' | tr -d '"' || true)
    definition=$(nav_code "$sources" | grep -E 'RELEASE_PACKAGES *: *Set<String> *=' | head -1 || true)
    if [ "$constant" != "$MAPS_PACKAGE" ]; then
      fail "$sources: GOOGLE_MAPS must be exactly $MAPS_PACKAGE (found '${constant:-nothing}')"
    fi
    if ! printf '%s' "$definition" | grep -qE '=[[:space:]]*setOf\([[:space:]]*GOOGLE_MAPS[[:space:]]*\)[[:space:]]*$'; then
      fail "$sources: the release allowlist must be exactly setOf(GOOGLE_MAPS) (found '${definition:-nothing}')"
    fi
  fi

  # d. A release or profile build adds no package and no capture tool.
  local variant build code
  for variant in release profile; do
    build="$NAV_SRC/$variant/$NAV_DIR/NavBuild.kt"
    if [ ! -f "$build" ]; then
      fail "$build is missing: a $variant build must add nothing to the listener"
      continue
    fi
    code=$(nav_code "$build")
    if ! printf '%s' "$code" | grep -qE 'fun extraPackages\([^)]*\): *Set<String> *= *emptySet\(\)'; then
      fail "$build: extraPackages must be emptySet()"
    fi
    if ! printf '%s' "$code" | grep -qE 'fun tap\([^)]*\): *NavTap\? *= *null'; then
      fail "$build: tap must be null"
    fi
  done

  # e. The package filter comes first. The listener never reads a notification
  # itself (the taps do, and only ever see ones that passed), and every call that
  # hands one on follows a check of its package.
  if nav_code "$service" | grep -vE '^[[:space:]]*(import|package) ' | grep -qE '\.notification([^A-Za-z0-9_]|$)|getNotification\('; then
    fail "$service reads a notification; only a NavTap may, after the package filter"
  fi
  if ! nav_code "$service" | awk '
      /isAllowed\(/ { last = NR }
      /(tap\?|NavBridge)\.(posted|removed)\(/ { if (last == 0 || NR - last > 4) bad = 1 }
      END { exit bad }'; then
    fail "$service hands a notification on without checking its package first"
  fi

  if [ "$FAILED" = 0 ]; then
    ok "the navigation listener reads one package, has no network code and filters first"
  fi
  if [ "$before" = 1 ]; then FAILED=1; fi
}

# ---- run --------------------------------------------------------------------

check_lockfile
check_dart
check_manifests
check_nav
check_gradle

if [ "$FAILED" = 0 ]; then
  echo "Offline check passed."
else
  echo "Offline check FAILED." >&2
  exit 1
fi
