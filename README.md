# AppCleaner-macOS
Interactive macOS CLI uninstaller that finds an app plus related leftover files (caches, containers, preferences, logs) and moves them to Trash.

AppCleaner is a Swift-based command-line app uninstaller for macOS. It scans /Applications and ~/Applications, lets you search/filter and pick an app, discovers common “leftover” files in ~/Library (and some /Library locations), shows sizes + total disk usage, then moves everything to Trash with a confirmation prompt.


How to use
This is a Swift Package Manager CLI. The executable target is appcleaner.

Open Terminal:
`cd /Users/daniel/Desktop/Project/AppCleaner/AppCleaner/cli &&
swift build -c release &&
cp .build/release/appcleaner /usr/local/bin/appcleaner`

and then and terminal call appcleaner
`appcleaner --help`
