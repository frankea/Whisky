//
//  WineRuntime.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//

import Foundation

public struct WineRuntime: Codable, Equatable, Identifiable, Sendable {
    public static let defaultIdentifier = "default"
    private static let defaultsKey = "registeredWineRuntimes"

    public let id: String
    public var name: String
    public var root: URL

    public init(id: String, name: String, root: URL) {
        self.id = id
        self.name = name
        self.root = root
    }

    public var binFolder: URL {
        if FileManager.default.fileExists(atPath: root.appending(path: "bin").path(percentEncoded: false)) {
            root.appending(path: "bin")
        } else {
            root.appending(path: "Wine").appending(path: "bin")
        }
    }

    public var libFolder: URL {
        if FileManager.default.fileExists(atPath: root.appending(path: "lib").path(percentEncoded: false)) {
            root.appending(path: "lib")
        } else {
            root.appending(path: "Wine").appending(path: "lib")
        }
    }

    public var libraryFolder: URL {
        if FileManager.default.fileExists(atPath: root.appending(path: "Wine").path(percentEncoded: false)) {
            root
        } else {
            root.deletingLastPathComponent()
        }
    }

    public var wineBinary: URL {
        if id == Self.defaultIdentifier {
            return binFolder.appending(path: "wine64")
        }
        let wine64 = binFolder.appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return binFolder.appending(path: "wine")
    }

    public var wineserverBinary: URL {
        binFolder.appending(path: "wineserver")
    }

    public var isUsable: Bool {
        FileManager.default.isExecutableFile(atPath: wineBinary.path(percentEncoded: false)) &&
            FileManager.default.isExecutableFile(atPath: wineserverBinary.path(percentEncoded: false))
    }

    public var statusDescription: String {
        guard isUsable else {
            return "Missing executable wine/wineserver"
        }
        return detectedWineVersion() ?? "Wine version unknown"
    }

    public static var `default`: WineRuntime {
        WineRuntime(
            id: defaultIdentifier,
            name: "Default (Wine 11.0)",
            root: WhiskyWineInstaller.libraryFolder
        )
    }

    public static var legacyWhiskyRuntime: WineRuntime {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
            .appending(path: "WhiskyLegacy")
            .appending(path: "Wine-7.7")
        return WineRuntime(id: "whiskylegacy-wine-7.7", name: "WhiskyLegacy Wine 7.7", root: root)
    }

    public static var registeredRuntimes: [WineRuntime] {
        get {
            var runtimes = loadRegisteredRuntimes()
            for runtime in discoveredRuntimes where !runtimes.contains(where: { $0.id == runtime.id }) {
                runtimes.append(runtime)
            }
            return runtimes
        }
        set {
            saveRegisteredRuntimes(newValue.filter { $0.id != defaultIdentifier })
        }
    }

    public static var availableRuntimes: [WineRuntime] {
        [Self.default] + registeredRuntimes
    }

    public static func runtime(for identifier: String?) -> WineRuntime {
        guard let identifier, identifier != defaultIdentifier else {
            return .default
        }
        return availableRuntimes.first(where: { $0.id == identifier }) ?? .default
    }

    @discardableResult
    public static func registerExternalRuntime(name: String, root: URL) -> WineRuntime {
        let normalizedRoot = normalizedRuntimeRoot(for: root) ?? root
        let id = runtimeIdentifier(for: normalizedRoot)
        let runtime = WineRuntime(id: id, name: name, root: normalizedRoot)
        var runtimes = registeredRuntimes.filter { $0.id != runtime.id && $0.root != runtime.root }
        runtimes.append(runtime)
        registeredRuntimes = runtimes
        return runtime
    }

    public static func unregisterExternalRuntime(_ runtime: WineRuntime) {
        registeredRuntimes = loadRegisteredRuntimes().filter { $0.id != runtime.id }
    }

    public static func isRegisteredRuntime(_ runtime: WineRuntime) -> Bool {
        loadRegisteredRuntimes().contains(where: { $0.id == runtime.id })
    }

    private static var discoveredRuntimes: [WineRuntime] {
        var runtimes: [WineRuntime] = []
        let defaultRoot = Self.default.root.standardizedFileURL

        for root in discoveredRuntimeRoots where root.standardizedFileURL != defaultRoot {
            let runtime = WineRuntime(
                id: runtimeIdentifier(for: root),
                name: runtimeName(for: root),
                root: root
            )
            if runtime.isUsable, !runtimes.contains(where: { $0.root.standardizedFileURL == root.standardizedFileURL }) {
                runtimes.append(runtime)
            }
        }
        return runtimes
    }

    private static var discoveredRuntimeRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appending(path: "Library").appending(path: "Application Support")
        let searchFolders = [
            appSupport.appending(path: "WhiskyLegacy"),
            appSupport.appending(path: "com.franke.Whisky").appending(path: "Runtimes"),
            appSupport.appending(path: "com.isaacmarovitz.Whisky")
        ]

        var roots = [legacyWhiskyRuntime.root]
        for folder in searchFolders {
            roots.append(contentsOf: runtimeRootCandidates(in: folder))
        }
        return roots.uniqueByStandardizedPath()
    }

    private static func runtimeRootCandidates(in folder: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [URL] = []
        for item in contents where item.isDirectory {
            candidates.append(item)
            candidates.append(item.appending(path: "Libraries"))
            candidates.append(item.appending(path: "Contents").appending(path: "Resources").appending(path: "wine"))
        }
        candidates.append(folder.appending(path: "Libraries"))
        return candidates.filter(isRuntimeRoot)
    }

    private static func isRuntimeRoot(_ root: URL) -> Bool {
        let runtime = WineRuntime(id: runtimeIdentifier(for: root), name: runtimeName(for: root), root: root)
        return runtime.isUsable
    }

    private static func normalizedRuntimeRoot(for root: URL) -> URL? {
        [
            root,
            root.appending(path: "Libraries"),
            root.appending(path: "Contents").appending(path: "Resources").appending(path: "wine")
        ].first(where: isRuntimeRoot)
    }

    private static func runtimeIdentifier(for root: URL) -> String {
        if root.standardizedFileURL.path(percentEncoded: false).hasSuffix("/WhiskyLegacy/Wine-7.7") {
            return legacyWhiskyRuntime.id
        }
        let sanitizedPath = root.standardizedFileURL.path(percentEncoded: false).unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return "external-\(sanitizedPath)"
    }

    private static func runtimeName(for root: URL) -> String {
        let path = root.standardizedFileURL.path(percentEncoded: false)
        if path.hasSuffix("/WhiskyLegacy/Wine-7.7") {
            return "WhiskyLegacy Wine 7.7"
        }
        if root.lastPathComponent == "Libraries" {
            return root.deletingLastPathComponent().lastPathComponent
        }
        if root.lastPathComponent == "wine" {
            return root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        }
        return root.lastPathComponent
    }

    private static func loadRegisteredRuntimes() -> [WineRuntime] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let runtimes = try? JSONDecoder().decode([WineRuntime].self, from: data) else {
            return []
        }
        return runtimes
    }

    private static func saveRegisteredRuntimes(_ runtimes: [WineRuntime]) {
        guard let data = try? JSONEncoder().encode(runtimes) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func detectedWineVersion() -> String? {
        let process = Process()
        process.executableURL = wineBinary
        process.arguments = ["--version"]
        process.environment = [
            "DYLD_FALLBACK_LIBRARY_PATH": libFolder.path(percentEncoded: false)
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private extension Array where Element == URL {
    func uniqueByStandardizedPath() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.standardizedFileURL.path(percentEncoded: false)).inserted
        }
    }
}
