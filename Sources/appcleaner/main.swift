import Foundation

let fileManager = FileManager.default
let homeDir = fileManager.homeDirectoryForCurrentUser

struct AppInfo {
    let name: String
    let path: URL
    let bundleId: String?
    let version: String?
}

func prompt(_ message: String) -> String {
    print(message, terminator: " ")
    return readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces) ?? ""
}

func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func readAppInfo(at url: URL) -> AppInfo {
    let plistURL = url.appendingPathComponent("Contents/Info.plist")
    let fallbackName = url.deletingPathExtension().lastPathComponent

    guard
        let data = try? Data(contentsOf: plistURL),
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    else {
        return AppInfo(name: fallbackName, path: url, bundleId: nil, version: nil)
    }

    let bundleId = plist["CFBundleIdentifier"] as? String
    let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String
    let displayName = (plist["CFBundleDisplayName"] as? String)
        ?? (plist["CFBundleName"] as? String)
        ?? fallbackName
    return AppInfo(name: displayName, path: url, bundleId: bundleId, version: version)
}

func discoverApps() -> [AppInfo] {
    let roots = [
        URL(fileURLWithPath: "/Applications"),
        homeDir.appendingPathComponent("Applications"),
    ]

    var apps: [AppInfo] = []
    var seen = Set<String>()

    for root in roots {
        guard fileManager.fileExists(atPath: root.path) else { continue }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { continue }

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                if !seen.insert(url.path).inserted { continue }
                enumerator.skipDescendants()
                apps.append(readAppInfo(at: url))
            }
        }
    }

    return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

func findLeftovers(for app: AppInfo) -> [URL] {
    var found: [URL] = []
    let userLib = homeDir.appendingPathComponent("Library")
    let sysLib = URL(fileURLWithPath: "/Library")

    let bundleIdDirs: [URL] = [
        userLib.appendingPathComponent("Containers"),
        userLib.appendingPathComponent("Caches"),
        userLib.appendingPathComponent("HTTPStorages"),
        userLib.appendingPathComponent("WebKit"),
        userLib.appendingPathComponent("Application Scripts"),
        userLib.appendingPathComponent("Preferences"),
        userLib.appendingPathComponent("Saved Application State"),
    ]

    let nameDirs: [URL] = [
        userLib.appendingPathComponent("Application Support"),
        userLib.appendingPathComponent("Logs"),
        userLib.appendingPathComponent("Caches"),
        sysLib.appendingPathComponent("Application Support"),
        sysLib.appendingPathComponent("Logs"),
        sysLib.appendingPathComponent("Caches"),
    ]

    func addIfExists(_ url: URL) {
        if fileManager.fileExists(atPath: url.path) { found.append(url) }
    }

    if let bid = app.bundleId, !bid.isEmpty {
        for dir in bundleIdDirs {
            addIfExists(dir.appendingPathComponent(bid))
            addIfExists(dir.appendingPathComponent("\(bid).plist"))
            addIfExists(dir.appendingPathComponent("\(bid).savedState"))
            addIfExists(dir.appendingPathComponent("\(bid).binarycookies"))
        }

        let cookies = userLib.appendingPathComponent("Cookies/\(bid).binarycookies")
        addIfExists(cookies)

        // Group containers — match anything containing the bundle id, or its
        // reverse-DNS prefix (vendor.product → vendor).
        let groupRoot = userLib.appendingPathComponent("Group Containers")
        if let entries = try? fileManager.contentsOfDirectory(at: groupRoot, includingPropertiesForKeys: nil) {
            let parts = bid.split(separator: ".")
            let vendorPrefix = parts.count > 1 ? parts.dropLast().joined(separator: ".") : bid
            for entry in entries {
                let n = entry.lastPathComponent
                if n.contains(bid) || (vendorPrefix.count >= 4 && n.contains(vendorPrefix)) {
                    found.append(entry)
                }
            }
        }

        // LaunchAgents / LaunchDaemons plists with this bundle id prefix.
        let launchDirs = [
            userLib.appendingPathComponent("LaunchAgents"),
            sysLib.appendingPathComponent("LaunchAgents"),
            sysLib.appendingPathComponent("LaunchDaemons"),
        ]
        for dir in launchDirs {
            guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.lastPathComponent.hasPrefix(bid) {
                found.append(entry)
            }
        }
    }

    for dir in nameDirs {
        addIfExists(dir.appendingPathComponent(app.name))
    }

    var seen = Set<String>()
    return found.filter { seen.insert($0.path).inserted }
}

func itemSize(_ url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
    var total: Int64 = 0

    if let values = try? url.resourceValues(forKeys: Set(keys)) {
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
    }

    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: []) {
        for case let f as URL in enumerator {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
    }
    return total
}

func formatSize(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

func moveToTrash(_ url: URL) -> Bool {
    do {
        var resulting: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resulting)
        return true
    } catch {
        stderr("  failed: \(url.path) — \(error.localizedDescription)")
        return false
    }
}

func selectApp(from apps: [AppInfo]) -> AppInfo? {
    var visible = apps
    while true {
        print("")
        for (i, app) in visible.enumerated() {
            let v = app.version.map { " (\($0))" } ?? ""
            print(String(format: "%4d. %@%@", i + 1, app.name, v))
        }
        print("")
        let answer = prompt("Enter number to remove, text to filter, or 'q' to quit:")
        if answer.isEmpty { continue }
        if answer.lowercased() == "q" { return nil }

        if let idx = Int(answer), idx >= 1, idx <= visible.count {
            return visible[idx - 1]
        }

        let filtered = apps.filter { $0.name.localizedCaseInsensitiveContains(answer) }
        if filtered.isEmpty {
            print("No matches for '\(answer)'. Showing full list again.")
            visible = apps
        } else {
            visible = filtered
        }
    }
}

func run() {
    print("AppCleaner — macOS app uninstaller")
    print("Scanning /Applications and ~/Applications...")

    let apps = discoverApps()
    if apps.isEmpty {
        print("No applications found.")
        return
    }
    print("Found \(apps.count) application(s).")

    guard let app = selectApp(from: apps) else {
        print("Cancelled.")
        return
    }

    print("")
    print("Selected: \(app.name)")
    if let bid = app.bundleId { print("Bundle ID: \(bid)") }
    print("Path:     \(app.path.path)")

    print("Searching for related files...")
    var items: [URL] = [app.path]
    items.append(contentsOf: findLeftovers(for: app))

    print("")
    print("Items to remove (\(items.count)):")
    var total: Int64 = 0
    for (i, url) in items.enumerated() {
        let size = itemSize(url)
        total += size
        print(String(format: "  %2d. [%10@] %@", i + 1, formatSize(size) as NSString, url.path))
    }
    print("")
    print("Total size: \(formatSize(total))")
    print("")

    let confirm = prompt("Move all these to Trash? (y/N):").lowercased()
    guard confirm == "y" || confirm == "yes" else {
        print("Cancelled.")
        return
    }

    var ok = 0, failed = 0
    for url in items {
        if moveToTrash(url) {
            ok += 1
            print("  trashed: \(url.path)")
        } else {
            failed += 1
        }
    }
    print("")
    print("Done. Trashed: \(ok), failed: \(failed).")
    if failed > 0 {
        print("Note: items in /Library or /Applications may need admin privileges.")
        print("Re-run with 'sudo' to remove those, or empty the Trash manually.")
    }
}

run()
