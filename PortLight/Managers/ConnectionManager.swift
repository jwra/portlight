import Foundation
import OSLog

@Observable
final class ConnectionManager {
    var config: AppConfig = AppConfig.defaultConfig
    var statuses: [String: ConnectionStatus] = [:]

    private var processes: [String: Process] = [:]
    private var errorPipes: [String: Pipe] = [:]
    private var readinessChecks: [String: DispatchWorkItem] = [:]
    private let logger = Logger(subsystem: "net.jwra.PortLight", category: "ConnectionManager")
    private let configManager: ConfigManager

    /// Maximum time to wait for proxy to become ready (seconds)
    private let connectionTimeoutSeconds: TimeInterval = 30
    /// Interval between port availability checks (seconds)
    private let pollIntervalSeconds: TimeInterval = 0.1

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
        let oldConfig = config
        let newConfig = configManager.loadConfig()

        let oldById = Dictionary(uniqueKeysWithValues: oldConfig.connections.map { ($0.id, $0) })
        let newById = Dictionary(uniqueKeysWithValues: newConfig.connections.map { ($0.id, $0) })

        // Disconnect removed connections
        for (id, _) in oldById where newById[id] == nil {
            cancelReadinessCheck(for: id)
            if let process = processes[id] {
                process.terminate()
                process.waitUntilExit()
                processes.removeValue(forKey: id)
                errorPipes.removeValue(forKey: id)
            }
            statuses.removeValue(forKey: id)
        }

        // Handle modified connections
        for (id, newConn) in newById {
            if let oldConn = oldById[id] {
                if newConn.requiresReconnect(comparedTo: oldConn) {
                    // Port changed - need to reconnect
                    cancelReadinessCheck(for: id)
                    if let process = processes[id] {
                        process.terminate()
                        process.waitUntilExit()
                        processes.removeValue(forKey: id)
                        errorPipes.removeValue(forKey: id)
                    }
                    statuses[id] = .disconnected
                }
                // Name or autoConnect changed - just let config update handle it
            } else {
                // New connection
                statuses[id] = .disconnected
            }
        }

        config = newConfig
        logger.info("Config reloaded with \(newConfig.connections.count) connections")
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

            waitForProxyReady(connection: connection, port: connection.port)
        } catch {
            setStatus(.error("Failed to start: \(error.localizedDescription)"), for: connection)
            logger.error("Failed to start proxy: \(error.localizedDescription)")
        }
    }

    func disconnect(_ connection: DBConnection) {
        logger.info("Disconnecting: \(connection.name)")

        cancelReadinessCheck(for: connection.id)

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
        for (id, _) in readinessChecks {
            cancelReadinessCheck(for: id)
        }
        for (_, process) in processes {
            process.terminate()
            process.waitUntilExit()
        }
        processes.removeAll()
        errorPipes.removeAll()
        for key in statuses.keys {
            statuses[key] = .disconnected
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
        let currentIds = Set(config.connections.map { $0.id })

        // Remove statuses for connections no longer in config
        for key in statuses.keys where !currentIds.contains(key) {
            statuses.removeValue(forKey: key)
        }

        // Add statuses for new connections
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

    /// Polls the port until the proxy is accepting connections or timeout occurs
    private func waitForProxyReady(connection: DBConnection, port: Int) {
        let startTime = Date()
        let connectionId = connection.id

        let workItem = DispatchWorkItem { [weak self] in
            self?.pollPortReadiness(
                connectionId: connectionId,
                port: port,
                startTime: startTime,
                connectionName: connection.name
            )
        }

        readinessChecks[connectionId] = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    private func pollPortReadiness(
        connectionId: String,
        port: Int,
        startTime: Date,
        connectionName: String
    ) {
        // Check if we should stop polling
        guard let workItem = readinessChecks[connectionId], !workItem.isCancelled else {
            return
        }

        // Check if process is still running
        guard processes[connectionId]?.isRunning == true else {
            readinessChecks.removeValue(forKey: connectionId)
            return
        }

        // Check if we're still in connecting state (might have errored via stderr)
        if case .connecting = statuses[connectionId] {
            // Continue checking
        } else {
            readinessChecks.removeValue(forKey: connectionId)
            return
        }

        // Check timeout
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed >= connectionTimeoutSeconds {
            logger.warning("Connection timeout for \(connectionName) after \(Int(elapsed))s")
            DispatchQueue.main.async { [weak self] in
                guard let self, case .connecting = self.statuses[connectionId] else { return }
                self.setStatus(.error("Connection timeout"), for: DBConnection(
                    name: connectionName,
                    instanceConnectionName: connectionId,
                    port: port
                ))
            }
            readinessChecks.removeValue(forKey: connectionId)
            return
        }

        // Try to connect to the port
        if canConnectToPort(port) {
            logger.info("Proxy ready for \(connectionName) on port \(port) after \(String(format: "%.1f", elapsed))s")
            DispatchQueue.main.async { [weak self] in
                guard let self, case .connecting = self.statuses[connectionId] else { return }
                self.setStatus(.connected, for: DBConnection(
                    name: connectionName,
                    instanceConnectionName: connectionId,
                    port: port
                ))
            }
            readinessChecks.removeValue(forKey: connectionId)
            return
        }

        // Schedule next poll
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + pollIntervalSeconds
        ) { [weak self] in
            self?.pollPortReadiness(
                connectionId: connectionId,
                port: port,
                startTime: startTime,
                connectionName: connectionName
            )
        }
    }

    /// Attempts a TCP connection to verify the proxy is accepting connections
    private func canConnectToPort(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        // Set non-blocking for quick timeout
        var flags = fcntl(socketFD, F_GETFL, 0)
        flags |= O_NONBLOCK
        fcntl(socketFD, F_SETFL, flags)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Check if connected or connection in progress
        if result == 0 {
            return true
        }

        // For non-blocking socket, EINPROGRESS means connection is being established
        if errno == EINPROGRESS {
            // Use select to wait briefly for connection
            var writeSet = fd_set()
            __darwin_fd_zero(&writeSet)
            __darwin_fd_set(socketFD, &writeSet)

            var timeout = timeval(tv_sec: 0, tv_usec: 50000) // 50ms timeout
            let selectResult = select(socketFD + 1, nil, &writeSet, nil, &timeout)

            if selectResult > 0 && __darwin_fd_isset(socketFD, &writeSet) != 0 {
                // Check if connection succeeded
                var error: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &len)
                return error == 0
            }
        }

        return false
    }

    private func cancelReadinessCheck(for connectionId: String) {
        readinessChecks[connectionId]?.cancel()
        readinessChecks.removeValue(forKey: connectionId)
    }
}
