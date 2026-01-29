import Foundation
import AppKit
import OSLog

@Observable
final class ConfigManager {
    private let logger = Logger(subsystem: "net.jwra.PortLight", category: "Config")
    private let fileManager = FileManager.default
    private var didLogFallback = false

    var configURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
    }

    var configDirectoryURL: URL {
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("PortLight")
        }

        // Fallback to home directory if Application Support unavailable
        if !didLogFallback {
            logger.warning("Application Support directory unavailable, using fallback location")
            didLogFallback = true
        }
        let homeDir = fileManager.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".portlight")
    }

    func loadConfig() -> AppConfig {
        ensureConfigDirectoryExists()

        if !fileManager.fileExists(atPath: configURL.path) {
            logger.info("No config found, creating default")
            saveConfig(AppConfig.defaultConfig)
        }

        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            logger.info("Loaded config with \(config.connections.count) connections")
            return config
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription)")
            return AppConfig.defaultConfig
        }
    }

    func saveConfig(_ config: AppConfig) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
            logger.info("Config saved")
        } catch {
            logger.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    func openConfigInEditor() {
        NSWorkspace.shared.open(configURL)
    }

    func revealConfigInFinder() {
        NSWorkspace.shared.selectFile(configURL.path, inFileViewerRootedAtPath: configDirectoryURL.path)
    }

    private func ensureConfigDirectoryExists() {
        guard !fileManager.fileExists(atPath: configDirectoryURL.path) else { return }
        do {
            try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
            logger.info("Created config directory")
        } catch {
            logger.error("Failed to create config directory: \(error.localizedDescription)")
        }
    }
}
