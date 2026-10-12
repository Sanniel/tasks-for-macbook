#!/bin/zsh
# Builds a Release version and installs it as /Applications/Tasks.app.
#
# Also makes sure macOS uses the installed copy for the widget and the widget's
# links: it removes the Debug build of the app (rebuild it when needed) and
# restarts the widget service, which otherwise keeps launching a cached copy.
set -euo pipefail
cd "${0:A:h}/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PRODUCTS=build/DerivedData/Build/Products

xcodebuild -project Tasks.xcodeproj -scheme Tasks -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates -quiet build

pkill -x Tasks || true
pkill -x TasksWidget || true
sleep 0.5

for app in "$PRODUCTS/Debug/Tasks.app" "$PRODUCTS/Release/Tasks.app"; do
  [[ -d $app ]] || continue
  pluginkit -r "$app/Contents/PlugIns/TasksWidget.appex" 2>/dev/null || true
  $LSREGISTER -u "$app" 2>/dev/null || true
done
rm -rf "$PRODUCTS/Debug/Tasks.app"

rm -rf /Applications/Tasks.app
ditto "$PRODUCTS/Release/Tasks.app" /Applications/Tasks.app
$LSREGISTER -f /Applications/Tasks.app
pluginkit -a /Applications/Tasks.app/Contents/PlugIns/TasksWidget.appex

killall chronod 2>/dev/null || true  # widget service; launchd restarts it
sleep 2
open /Applications/Tasks.app
echo "Installed /Applications/Tasks.app"
