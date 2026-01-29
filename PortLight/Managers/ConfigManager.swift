import Foundation
import AppKit
import OSLog

@Observable
final class ConfigManager {
    private let logger = Logger(subsystem: "net.jwra.PortLight", category: "Config")
    private let fileManager = FileManager.default
    private var didLogFallback = false

    /// Last validation result from config loading - publicly readable for UI
    var lastValidationResult: ConfigValidationResult?

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

            // Validate and log issues
            let validation = config.validate()
            lastValidationResult = validation
            logValidationIssues(validation)

            return config
        } catch {
            logger.error("Failed to load config: \(error.localizedDescription)")
            lastValidationResult = nil
            return AppConfig.defaultConfig
        }
    }

    private func logValidationIssues(_ result: ConfigValidationResult) {
        for error in result.allErrors {
            logger.error("Config error [\(error.field)]: \(error.message)")
        }
        for warning in result.allWarnings {
            logger.warning("Config warning [\(warning.field)]: \(warning.message)")
        }
        if result.isValid && !result.hasWarnings {
            logger.info("Config validation passed")
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
