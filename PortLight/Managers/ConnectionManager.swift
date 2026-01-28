import Foundation
import OSLog

@Observable
final class ConnectionManager {
    var config: AppConfig = AppConfig.defaultConfig
    var statuses: [UUID: ConnectionStatus] = [:]

    private var processes: [UUID: Process] = [:]
    private var errorPipes: [UUID: Pipe] = [:]
    private let logger = Logger(subsystem: "net.jwra.PortLight", category: "ConnectionManager")
    private let configManager: ConfigManager

    var hasActiveConnections: Bool {
        statuses.values.contains { $0.isActive }
    }

    var menuBarIcon: String {
        if statuses.values.contains(where: { if case .error = $0 { return true }; return false }) {
            return "bolt.trianglebadge.exclamationmark"
        } else if hasActiveConnections {
            return "bolt.fill"
        } else {
            return "bolt"
        }
    }

    init(configManager: ConfigManager = ConfigManager()) {
        self.configManager = configManager
    }

    func setup() {
        loadConfig()
        initializeStatuses()
        handleAutoConnect()
    }

    func loadConfig() {
        config = configManager.loadConfig()
    }

    func reloadConfig() {
        disconnectAll()
        loadConfig()
        initializeStatuses()
        handleAutoConnect()
    }

    func status(for connection: DBConnection) -> ConnectionStatus {
        statuses[connection.id] ?? .disconnected
    }

    func toggle(_ connection: DBConnection) {
        if status(for: connection).isActive {
            disconnect(connection)
        } else {
            connect(connection)
        }
    }

    func connect(_ connection: DBConnection) {
        logger.info("Connecting: \(connection.name)")

        guard FileManager.default.isExecutableFile(atPath: config.binaryPath) else {
            setStatus(.error("cloud-sql-proxy not found at \(config.binaryPath)"), for: connection)
            logger.error("Binary not found at: \(self.config.binaryPath)")
            return
        }

        if let conflict = config.connections.first(where: {
            $0.id != connection.id &&
            $0.port == connection.port &&
            statuses[$0.id]?.isActive == true
        }) {
            setStatus(.error("Port \(connection.port) used by \(conflict.name)"), for: connection)
            return
        }

        if !isPortAvailable(connection.port) {
            setStatus(.error("Port \(connection.port) in use"), for: connection)
            return
        }

        setStatus(.connecting, for: connection)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.binaryPath)
        process.arguments = [
            connection.instanceConnectionName,
            "--port", "\(connection.port)"
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        process.terminationHandler = { [weak self] terminated in
            DispatchQueue.main.async {
                self?.handleProcessTermination(terminated, connection: connection)
            }
        }

        monitorStderr(errorPipe, for: connection)

        do {
            try process.run()
            processes[connection.id] = process
            errorPipes[connection.id] = errorPipe

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard self?.processes[connection.id]?.isRunning == true else { return }
                if case .connecting = self?.statuses[connection.id] {
                    self?.setStatus(.connected, for: connection)
                }
            }
        } catch {
            setStatus(.error("Failed to start: \(error.localizedDescription)"), for: connection)
            logger.error("Failed to start proxy: \(error.localizedDescription)")
        }
    }

    func disconnect(_ connection: DBConnection) {
        logger.info("Disconnecting: \(connection.name)")

        guard let process = processes[connection.id] else {
            setStatus(.disconnected, for: connection)
            return
        }

        process.terminate()
        process.waitUntilExit()

        processes.removeValue(forKey: connection.id)
        errorPipes.removeValue(forKey: connection.id)
        setStatus(.disconnected, for: connection)
    }

    func disconnectAll() {
        for connection in config.connections {
            disconnect(connection)
        }
    }

    func shutdown() {
        logger.info("Shutting down all connections")
        disconnectAll()
    }

    func openConfig() {
        configManager.openConfigInEditor()
    }

    func revealConfig() {
        configManager.revealConfigInFinder()
    }

    private func initializeStatuses() {
        for connection in config.connections where statuses[connection.id] == nil {
            statuses[connection.id] = .disconnected
        }
    }

    private func handleAutoConnect() {
        let autoConnectList = config.connections.filter { $0.autoConnect }
        for connection in autoConnectList {
            connect(connection)
        }
        if !autoConnectList.isEmpty {
            logger.info("Auto-connected \(autoConnectList.count) connections")
        }
    }

    private func setStatus(_ status: ConnectionStatus, for connection: DBConnection) {
        DispatchQueue.main.async {
            self.statuses[connection.id] = status
        }
    }

    private func handleProcessTermination(_ process: Process, connection: DBConnection) {
        let exitCode = process.terminationStatus

        processes.removeValue(forKey: connection.id)
        errorPipes.removeValue(forKey: connection.id)

        if exitCode != 0 && exitCode != 15 {
            setStatus(.error("Exited with code \(exitCode)"), for: connection)
            logger.error("Proxy for \(connection.name) exited with code \(exitCode)")
        } else {
            setStatus(.disconnected, for: connection)
        }
    }

    private func monitorStderr(_ pipe: Pipe, for connection: DBConnection) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            if output.lowercased().contains("error") || output.lowercased().contains("failed") {
                DispatchQueue.main.async {
                    let message = self?.extractErrorMessage(from: output) ?? "Connection failed"
                    self?.setStatus(.error(message), for: connection)
                }
            }
        }
    }

    private func extractErrorMessage(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error") || lower.contains("failed") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.count > 100 ? String(trimmed.prefix(100)) + "..." : trimmed
            }
        }
        return String(output.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }
}
