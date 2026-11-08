import Foundation

/// Identifies the running copy of Relay, so it is clear which build is open.
struct RelayBuildInfo {
    let version: String
    let build: String
    let commit: String?
    let builtAt: String?
    let launchMode: String
    let configuration: String
    let executableModified: Date?

    static let current: RelayBuildInfo = {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundled = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let modified = (try? FileManager.default.attributesOfItem(atPath: executable.path)[.modificationDate]) as? Date
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        return RelayBuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "unbundled",
            build: info["CFBundleVersion"] as? String ?? "development",
            commit: info["RelayGitCommit"] as? String,
            builtAt: info["RelayBuildDate"] as? String,
            launchMode: bundled ? "App bundle: \(Bundle.main.bundleURL.path)" : "Unbundled executable (swift run or Xcode)",
            configuration: configuration,
            executableModified: modified)
    }()
}
