#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
label=com.indivisual.WOLFullWake
service="system/$label"
service_plist="/Library/LaunchDaemons/$label.plist"
app_bundle="$project_root/dist/WakeLight.app"
installed_app=/Applications/WakeLight.app

"$project_root/scripts/build-app.sh"
/usr/bin/codesign --verify --strict "$app_bundle"
/usr/bin/sudo -v

# Prepare the new bundle before stopping the working service.
staging=$(/usr/bin/sudo /usr/bin/mktemp -d /Applications/.WakeLight.XXXXXX)
changed_service=false
was_running=false
installed_new_app=false
committed=false

cleanup() {
    result=$?
    trap - EXIT
    if [ "$committed" = false ]; then
        if [ "$changed_service" = true ]; then
            /usr/bin/sudo /bin/launchctl bootout "$service" 2>/dev/null || true
        fi
        if [ "$installed_new_app" = true ]; then
            /usr/bin/sudo /bin/mv "$installed_app" "$staging/failed.app" || exit 1
        fi
        if /usr/bin/sudo /bin/test -e "$staging/previous.app"; then
            /usr/bin/sudo /bin/mv "$staging/previous.app" "$installed_app" || exit 1
        fi
        if [ "$changed_service" = true ]; then
            if /usr/bin/sudo /bin/test -f "$staging/previous.plist"; then
                /usr/bin/sudo /bin/mv "$staging/previous.plist" "$service_plist" || exit 1
            else
                /usr/bin/sudo /bin/rm -f "$service_plist" || exit 1
            fi
            if [ "$was_running" = true ]; then
                /usr/bin/sudo /bin/launchctl bootstrap system "$service_plist" || exit 1
            fi
        fi
    fi
    /usr/bin/sudo /bin/rm -rf "$staging"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

/usr/bin/sudo /usr/bin/ditto "$app_bundle" "$staging/WakeLight.app"
/usr/bin/sudo /usr/sbin/chown -R root:wheel "$staging/WakeLight.app"
/usr/bin/sudo /bin/chmod -R go-w "$staging/WakeLight.app"
/usr/bin/sudo /usr/bin/codesign --verify --strict "$staging/WakeLight.app"
if [ -f "$service_plist" ]; then
    /usr/bin/sudo /bin/cp -p "$service_plist" "$staging/previous.plist"
fi

if /bin/launchctl print "$service" >/dev/null 2>&1; then
    /usr/bin/sudo /bin/launchctl bootout "$service"
    was_running=true
fi
changed_service=true

if [ -e "$installed_app" ] || [ -L "$installed_app" ]; then
    /usr/bin/sudo /bin/mv "$installed_app" "$staging/previous.app"
fi
/usr/bin/sudo /bin/mv "$staging/WakeLight.app" "$installed_app"
installed_new_app=true
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 0644 \
    "$project_root/Packaging/$label.plist" "$service_plist"
/usr/bin/sudo /bin/launchctl enable "$service"
/usr/bin/sudo /bin/launchctl bootstrap system "$service_plist"
committed=true
/bin/launchctl print "$service"
