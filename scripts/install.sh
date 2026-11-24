#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
label=com.indivisual.WOLFullWake
app_bundle="$project_root/dist/WakeLight.app"
helper_directory=/Library/PrivilegedHelperTools
service_plist="/Library/LaunchDaemons/$label.plist"

"$project_root/scripts/build-app.sh"

/usr/bin/sudo -v
if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
    /usr/bin/sudo /bin/launchctl bootout "system/$label"
fi
if [ ! -d "$helper_directory" ]; then
    /usr/bin/sudo /usr/bin/install -d -o root -g wheel -m 0755 "$helper_directory"
fi
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 0755 \
    "$app_bundle/Contents/MacOS/WakeLight" "$helper_directory/$label"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 0644 \
    "$project_root/Packaging/$label.plist" "$service_plist"
/usr/bin/sudo /bin/launchctl enable "system/$label"
/usr/bin/sudo /bin/launchctl bootstrap system "$service_plist"
/bin/launchctl print "system/$label"
