#!/bin/sh
# Executed ONLY after the user's macOS administrator authorization. The app
# passes this entire script by value, not a writable script path, to osascript.
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077
test "$(id -u)" = 0 || { echo 'Administrator authorization required' >&2; exit 1; }
mode=${1:-}
case "$mode" in install|uninstall) ;; *) exit 64;; esac
base=/Library/PrivilegedHelperTools
app=/Applications/Aidente.app
fail() { echo "Aidente installer: $1" >&2; exit 65; }

# Single source of truth: Shared/LocalControlIdentity.swift. build_app.sh
# renders the launchd manifest from those constants into
# Contents/Resources/install-launchd.plist; this script derives label, helper
# destination and system plist path from that manifest and hardcodes nothing.
label=''
dest=''
plist=''
bundled_manifest="$app/Contents/Resources/install-launchd.plist"
installed_plist=''
resolve_installed_daemon() {
    # Locate an already-installed Aidente daemon without hardcoding its label:
    # any LaunchDaemons plist whose ProgramArguments[0] runs AidenteControl
    # from the privileged helper tools directory.
    for candidate in /Library/LaunchDaemons/*.plist; do
        test -f "$candidate" || continue
        prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$candidate" 2>/dev/null) || continue
        case "$prog" in "$base"/*/AidenteControl)
            installed_plist=$candidate
            label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$candidate")
            dest=${prog%/*}
            plist=$candidate
            return 0
        ;; esac
    done
    return 1
}
case "$mode" in
    install)
        test ! -L "$app" && test -d "$app" || fail 'Aidente must be a real application in /Applications'
        test -f "$bundled_manifest" || fail 'Bundled launchd manifest missing'
        label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$bundled_manifest")
        prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$bundled_manifest")
        mach=$(/usr/libexec/PlistBuddy -c "Print :MachServices:$label" "$bundled_manifest" 2>/dev/null) || true
        test "$label" != '' || fail 'Bundled launchd manifest has no label'
        test "$mach" = true || fail 'Bundled launchd manifest MachServices mismatch'
        case "$prog" in "$base"/*/AidenteControl) ;;
            *) fail 'Bundled launchd manifest points outside the helper tools directory';;
        esac
        dest=${prog%/*}
        plist="/Library/LaunchDaemons/$label.plist"
    ;;
    uninstall)
        # The app may already be gone; resolve from the installed daemon instead.
        if resolve_installed_daemon; then
            : # label / dest / plist populated
        else
            # Fallback: a helper directory may linger without its launchd plist.
            for candidate in "$base"/*/AidenteControl; do
                test -x "$candidate" || continue
                dest=${candidate%/AidenteControl}
            done
        fi
    ;;
esac

# Reject redirected or user-writable privileged destinations.
safe_directory() {
    test -d "$1" && test ! -L "$1" || fail "Not a real directory: $1"
    test "$(stat -f %u "$1")" = 0 || fail "Directory is not administrator-owned: $1"
    permissions=$(stat -f %Lp "$1")
    test $((0$permissions & 0022)) = 0 || fail "Directory permits non-owner writes: $1"
}
safe_directory /Library
if test ! -e "$base"; then install -d -o root -g wheel -m 755 "$base"; fi
safe_directory "$base"
safe_directory /Library/LaunchDaemons
test ! -L "$dest" && test ! -L "$plist" || fail 'Service destination is a symbolic link'
if test -e "$dest"; then safe_directory "$dest"; fi
if test -e "$plist"; then
    test -f "$plist" && test "$(stat -f %u "$plist")" = 0 || fail 'Existing launch configuration has unsafe ownership/type'
fi

stage=$(mktemp -d "$base/.aidente-local.XXXXXXXX")
changed=0
rollback() {
    result=$?
    trap - EXIT
    if test "$result" != 0 && test "$changed" = 1; then
        launchctl bootout "system/$label" >/dev/null 2>&1 || true
        if test -e "$dest"; then mv "$dest" "$stage/failed-service"; fi
        if test -e "$plist"; then mv "$plist" "$stage/failed-launch.plist"; fi
        if test -d "$stage/previous-service"; then mv "$stage/previous-service" "$dest"; fi
        if test -f "$stage/previous-launch.plist"; then
            mv "$stage/previous-launch.plist" "$plist"
            launchctl bootstrap system "$plist" >/dev/null 2>&1 || true
        fi
        echo 'Installation failed; previous local service restored when available.' >&2
    fi
    exit "$result"
}
trap rollback EXIT

if test "$mode" = uninstall; then
    # Restore the battery BEFORE removing its only privileged recovery tool.
    if test -f "$dest/AidenteControl"; then
        test ! -L "$dest/AidenteControl" || fail 'Installed helper is a symbolic link'
        test "$(stat -f %u "$dest/AidenteControl")" = 0 || fail 'Installed helper is not administrator-owned'
        codesign --verify --strict "$dest/AidenteControl"
        launchctl bootout "system/$label" >/dev/null 2>&1 || true
        if ! "$dest/AidenteControl" --restore-local-defaults; then
            launchctl bootstrap system "$plist" >/dev/null 2>&1 || true
            echo 'Battery restore failed; service retained.' >&2
            exit 1
        fi
        mv "$dest" "$stage/removed-service"
    fi
    if test -f "$plist"; then mv "$plist" "$stage/removed-launch.plist"; fi
    echo "UNINSTALLED; recovery backup: $stage"
    exit 0
fi

helper_sha=${2:-}
client_sha=${3:-}
client_cdhash=${4:-}
test ${#helper_sha} = 64 && test ${#client_sha} = 64 && test ${#client_cdhash} = 40 || exit 64
case "$helper_sha$client_sha$client_cdhash" in *[!0-9a-f]*) exit 64;; esac
test ! -L "$app" && test -d "$app" || fail 'Aidente must be a real application in /Applications'
codesign --verify --deep --strict "$app"
mkdir "$stage/new-service"
cp "$app/Contents/MacOS/AidenteControl" "$stage/new-service/AidenteControl"
cp "$app/Contents/MacOS/Aidente" "$stage/client-snapshot"
actual_helper=$(shasum -a 256 "$stage/new-service/AidenteControl" | cut -d ' ' -f 1)
actual_client=$(shasum -a 256 "$stage/client-snapshot" | cut -d ' ' -f 1)
test "$actual_helper" = "$helper_sha" || fail 'Helper SHA-256 changed during installation'
test "$actual_client" = "$client_sha" || fail 'Application SHA-256 changed during installation'
# macOS codesign only includes CDHash with verbosity >= 3.
actual_cdhash=$(codesign -dvvv "$stage/client-snapshot" 2>&1 | sed -n 's/^CDHash=//p')
test -n "$actual_cdhash" || fail 'Could not read application CDHash'
test "$actual_cdhash" = "$client_cdhash" || fail 'Application CDHash does not match the authorized build'
codesign --verify --strict "$stage/new-service/AidenteControl"
chmod 755 "$stage/new-service" "$stage/new-service/AidenteControl"
/usr/libexec/PlistBuddy -c "Add :clientCDHash string $client_cdhash" "$stage/new-service/client.plist"
/usr/libexec/PlistBuddy -c "Add :clientSHA256 string $client_sha" "$stage/new-service/client.plist"
/usr/libexec/PlistBuddy -c "Add :helperSHA256 string $helper_sha" "$stage/new-service/client.plist"
chmod 644 "$stage/new-service/client.plist"
# Launchd manifest comes from the bundle, rendered by build_app.sh from
# Shared/LocalControlIdentity.swift (single source of truth).
cp "$bundled_manifest" "$stage/new-launch.plist"
chmod 644 "$stage/new-launch.plist"
plutil -lint "$stage/new-launch.plist"
launchctl bootout "system/$label" >/dev/null 2>&1 || true
changed=1
if test -e "$dest"; then mv "$dest" "$stage/previous-service"; fi
if test -e "$plist"; then mv "$plist" "$stage/previous-launch.plist"; fi
mv "$stage/new-service" "$dest"
mv "$stage/new-launch.plist" "$plist"
launchctl enable "system/$label"
launchctl bootstrap system "$plist"
launchctl kickstart "system/$label"
sleep 1
launchctl print "system/$label" | grep -q 'state = running'
changed=0
echo "INSTALLED; recovery backup: $stage"
