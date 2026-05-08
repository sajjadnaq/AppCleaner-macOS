# AppCleaner-macOS
Interactive macOS CLI uninstaller that finds an app plus related leftover files (caches, containers, preferences, logs) and moves them to Trash.

AppCleaner is a Swift-based command-line app uninstaller for macOS. It scans /Applications and ~/Applications, lets you search/filter and pick an app, discovers common “leftover” files in ~/Library (and some /Library locations), shows sizes + total disk usage, then moves everything to Trash with a confirmation prompt.
