#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=SysMonitor.app
rm -rf $APP; mkdir -p $APP/Contents/MacOS
swiftc -O main.swift SMC.swift -o $APP/Contents/MacOS/SysMonitor
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SysMonitor</string>
<key>CFBundleIdentifier</key><string>com.tahir.sysmonitor</string>
<key>CFBundleName</key><string>SysMonitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - $APP
echo "Built $APP"
