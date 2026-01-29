import Foundation
import OSLog

@Observable
final class ConnectionManager {
    var config: AppConfig = AppConfig.defaultConfig
    var statuses: [String: ConnectionStatus] = [:]

    /// The most recent error (connection name and message)
    var lastError: (connectionName: String, message: String)?

    private var processes: [String: Process] = [:]
    private var errorPipes: [String: Pipe] = [:]
    private var stderrBuffers: [String: String] = [:]  // Buffers stderr output per connection
    private var readinessChecks: [String: DispatchWorkItem] = [:]
    private let logger = Logger(subsystem: "net.jwra.PortLight", category: "ConnectionManager")
    let configManager: ConfigManager

    /// Serial queue for thread-safe access to processes, errorPipes, and readinessChecks
    private let stateQueue = DispatchQueue(label: "net.jwra.PortLight.ConnectionManager.state")

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
        setupConfigObserver()
    }

    private func setupConfigObserver() {
        configManager.onConnectionsChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.reloadConfig()
            }
        }
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

        // Collect processes that need to be terminated
        var processesToTerminate: [(id: String, process: Process)] = []

        // Find removed connections
        for (id, _) in oldById where newById[id] == nil {
            stateQueue.sync {
                cancelReadinessCheckUnsafe(for: id)
                if let process = processes[id] {
                    processesToTerminate.append((id: id, process: process))
                }
            }
            removeStatus(for: id)
        }

        // Handle modified connections
        for (id, newConn) in newById {
            if let oldConn = oldById[id] {
                if newConn.requiresReconnect(comparedTo: oldConn) {
                    // Port changed - need to reconnect
                    stateQueue.sync {
                        cancelReadinessCheckUnsafe(for: id)
                        if let process = processes[id] {
                            processesToTerminate.append((id: id, process: process))
                        }
                    }
                    setStatus(.disconnected, for: id)
                }
                // Name or autoConnect changed - just let config update handle it
            } else {
                // New connection
                setStatus(.disconnected, for: id)
            }
        }

        // Terminate processes and wait on background thread
        if !processesToTerminate.isEmpty {
            // Terminate all first (non-blocking)
            for (_, process) in processesToTerminate {
                process.terminate()
            }

            // Wait for exits and cleanup on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                for (_, process) in processesToTerminate {
                    process.waitUntilExit()
                }

                self?.stateQueue.sync {
                    for (id, _) in processesToTerminate {
                        self?.processes.removeValue(forKey: id)
                        self?.cleanupPipeUnsafe(for: id)
                    }
                }
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

        // Pre-connect validation
        let validationIssues = connection.validate()
        let errors = validationIssues.filter { $0.isError }
        if !errors.isEmpty {
            let errorMessage = errors.map { $0.message }.joined(separator: "; ")
            setStatus(.error(errorMessage), for: connection.id)
            logger.error("Validation failed for \(connection.name): \(errorMessage)")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: config.binaryPath) else {
            setStatus(.error("cloud-sql-proxy not found at \(config.binaryPath)"), for: connection.id)
            logger.error("Binary not found at: \(self.config.binaryPath)")
            return
        }

        if let conflict = config.connections.first(where: {
            $0.id != connection.id &&
            $0.port == connection.port &&
            statuses[$0.id]?.isActive == true
        }) {
            setStatus(.error("Port \(connection.port) used by \(conflict.name)"), for: connection.id)
            return
        }

        if !isPortAvailable(connection.port) {
            setStatus(.error("Port \(connection.port) in use"), for: connection.id)
            return
        }

        setStatus(.connecting, for: connection.id)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.binaryPath)
        process.arguments = [
            connection.instanceConnectionName,
            "--port", "\(connection.port)"
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        let connectionId = connection.id
        process.terminationHandler = { [weak self] terminated in
            DispatchQueue.main.async {
                self?.handleProcessTermination(terminated, connectionId: connectionId)
            }
        }

        monitorStderr(errorPipe, for: connection.id)

        do {
            try process.run()
            stateQueue.sync {
                processes[connection.id] = process
                errorPipes[connection.id] = errorPipe
            }

            waitForProxyReady(connectionId: connection.id, port: connection.port, connectionName: connection.name)
        } catch {
            setStatus(.error("Failed to start: \(error.localizedDescription)"), for: connection.id)
            logger.error("Failed to start proxy: \(error.localizedDescription)")
        }
    }

    func disconnect(_ connection: DBConnection) {
        logger.info("Disconnecting: \(connection.name)")
        let connectionId = connection.id

        let process: Process? = stateQueue.sync {
            cancelReadinessCheckUnsafe(for: connectionId)
            return processes[connectionId]
        }

        guard let process else {
            setStatus(.disconnected, for: connectionId)
            return
        }

        // Terminate the process
        process.terminate()

        // Wait for exit on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            process.waitUntilExit()

            self?.stateQueue.sync {
                self?.processes.removeValue(forKey: connectionId)
                self?.cleanupPipeUnsafe(for: connectionId)
            }

            DispatchQueue.main.async {
                guard let self else {
                    Logger(subsystem: "net.jwra.PortLight", category: "ConnectionManager")
                        .warning("Self deallocated during disconnect for \(connectionId)")
                    return
                }
                // Only set to disconnected if not already in error state from termination handler
                if case .error = self.statuses[connectionId] {
                    // Keep error state
                } else {
                    self.setStatus(.disconnected, for: connectionId)
                }
            }
        }
    }

    func disconnectAll() {
        let allProcesses: [Process] = stateQueue.sync {
            for (id, _) in readinessChecks {
                cancelReadinessCheckUnsafe(for: id)
            }
            let procs = Array(processes.values)
            return procs
        }

        // Set all statuses to disconnected immediately for responsive UI
        // Collect keys first to avoid mutating during iteration
        let connectionIds = Array(statuses.keys)
        for connectionId in connectionIds {
            setStatus(.disconnected, for: connectionId)
        }

        // Terminate all processes
        for process in allProcesses {
            process.terminate()
        }

        // Wait for exits on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for process in allProcesses {
                process.waitUntilExit()
            }

            self?.stateQueue.sync {
                self?.processes.removeAll()
                self?.cleanupAllPipesUnsafe()
            }
        }
    }

    func shutdown() {
        logger.info("Shutting down all connections")
        disconnectAll()
    }

    private func initializeStatuses() {
        let currentIds = Set(config.connections.map { $0.id })

        // Remove statuses for connections no longer in config
        // Collect keys first to avoid mutating during iteration
        let keysToRemove = statuses.keys.filter { !currentIds.contains($0) }
        for key in keysToRemove {
            removeStatus(for: key)
        }

        // Add statuses for new connections
        for connection in config.connections where statuses[connection.id] == nil {
            setStatus(.disconnected, for: connection.id)
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

    /// Sets the connection status, ensuring thread-safe access to the `statuses` dictionary.
    /// This method can be called from any thread - it will dispatch to main if needed.
    /// All status mutations MUST go through this method to prevent race conditions.
    private func setStatus(_ status: ConnectionStatus, for connectionId: String) {
        if Thread.isMainThread {
            statuses[connectionId] = status

            // Track the most recent error
            if case .error(let message) = status {
                let connectionName = config.connections.first { $0.id == connectionId }?.name ?? connectionId
                lastError = (connectionName: connectionName, message: message)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setStatus(status, for: connectionId)
            }
        }
    }

    /// Removes the status for a connection, ensuring thread-safe access to the `statuses` dictionary.
    /// This method can be called from any thread - it will dispatch to main if needed.
    /// All status removals MUST go through this method to prevent race conditions.
    private func removeStatus(for connectionId: String) {
        if Thread.isMainThread {
            statuses.removeValue(forKey: connectionId)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.removeStatus(for: connectionId)
            }
        }
    }

    /// Clears the last error banner
    func clearError() {
        lastError = nil
    }

    private func handleProcessTermination(_ process: Process, connectionId: String) {
        let exitCode = process.terminationStatus

        // Get the buffered stderr and clean up state
        // Do this in a single sync block to avoid race conditions
        let finalStderr: String = stateQueue.sync {
            // Clear the handler first to stop callbacks
            if let pipe = errorPipes[connectionId] {
                pipe.fileHandleForReading.readabilityHandler = nil
            }

            // Get the buffered output
            let buffer = stderrBuffers[connectionId] ?? ""

            // Clean up all state for this connection
            stderrBuffers.removeValue(forKey: connectionId)
            processes.removeValue(forKey: connectionId)
            errorPipes.removeValue(forKey: connectionId)

            return buffer
        }

        // Handle clean termination: exit code 0, 15 (raw SIGTERM), or 143 (128 + SIGTERM)
        let isCleanExit = exitCode == 0 || exitCode == 15 || exitCode == 143
        if !isCleanExit {
            // Try to extract a meaningful error message from stderr
            var errorMessage = "Connection failed (exit code \(exitCode))"
            if !finalStderr.isEmpty {
                // Log the raw error for debugging
                logger.error("Proxy stderr for \(connectionId): \(finalStderr)")

                // Convert to user-friendly message
                errorMessage = userFriendlyError(from: finalStderr)
            }
            logger.error("Proxy for \(connectionId) exited with code \(exitCode)")
            setStatus(.error(errorMessage), for: connectionId)
        } else {
            setStatus(.disconnected, for: connectionId)
        }
    }

    private func monitorStderr(_ pipe: Pipe, for connectionId: String) {
        // Initialize stderr buffer
        stateQueue.sync {
            stderrBuffers[connectionId] = ""
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }

            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            // Buffer all stderr output for later use in termination handler
            self.stateQueue.sync {
                self.stderrBuffers[connectionId, default: ""] += output
            }

            // Also check for errors immediately for responsive feedback
            if self.parseProxyError(from: output) != nil {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Only set error if still in connecting/connected state
                    let currentStatus = self.statuses[connectionId]
                    if case .connecting = currentStatus {
                        let friendlyMessage = self.userFriendlyError(from: output)
                        self.setStatus(.error(friendlyMessage), for: connectionId)
                    } else if case .connected = currentStatus {
                        let friendlyMessage = self.userFriendlyError(from: output)
                        self.setStatus(.error(friendlyMessage), for: connectionId)
                    }
                }
            }
        }
    }

    /// Parses cloud-sql-proxy stderr output for actual errors, avoiding false positives
    /// Returns nil if no real error is detected
    private func parseProxyError(from output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Check for false positive patterns first
            let lower = trimmed.lowercased()
            if isFalsePositive(lower) {
                continue
            }

            // Check for known error patterns from cloud-sql-proxy
            if let errorMessage = extractKnownErrorPattern(from: trimmed, lowercase: lower) {
                return truncateMessage(errorMessage)
            }
        }

        return nil
    }

    /// Checks if the line is a false positive (contains "error" but isn't actually an error)
    private func isFalsePositive(_ lowercaseLine: String) -> Bool {
        let falsePositivePatterns = [
            "error recovery",
            "no error",
            "errors: 0",
            "without error",
            "error-free",
            "error count: 0",
            "0 errors",
            "recovered from error",
            "error handling",
        ]
        return falsePositivePatterns.contains { lowercaseLine.contains($0) }
    }

    /// Extracts error message from known cloud-sql-proxy error patterns
    /// Returns the line if it matches an error pattern, nil otherwise
    private func extractKnownErrorPattern(from line: String, lowercase: String) -> String? {
        // Pattern 1: Explicit ERROR/FATAL prefix (common log format)
        let prefixPatterns = ["error:", "fatal:", "err:"]
        for prefix in prefixPatterns {
            if lowercase.hasPrefix(prefix) {
                return line  // Return full line, let userFriendlyError handle extraction
            }
        }

        // Pattern 2: Bracketed log level - just check for presence
        if lowercase.contains("[error]") || lowercase.contains("[fatal]") || lowercase.contains("[err]") {
            return line
        }

        // Pattern 3: Specific cloud-sql-proxy error indicators
        let errorIndicators = [
            "terminal error",
            "unable to start",
            "credentials",
            "could not find default credentials",
            "invalid instance",
            "instance not found",
            "project not found",
            "failed to refresh",
            "failed to create",
            "error initializing",
            "connection refused",
            "connection reset",
            "connection timed out",
            "unable to connect",
            "cannot connect",
            "dial tcp",
            "no such host",
            "name resolution",
            "permission denied",
            "authentication failed",
            "auth failed",
            "unauthorized",
            "forbidden",
            "certificate",
            "tls handshake",
        ]

        for indicator in errorIndicators {
            if lowercase.contains(indicator) {
                return line
            }
        }

        // Pattern 4: Generic "failed" with error context
        if lowercase.contains("failed to") || lowercase.contains("has failed") ||
           lowercase.contains("connection failed") || lowercase.contains("proxy failed") {
            return line
        }

        return nil
    }

    private func truncateMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 120 ? String(trimmed.prefix(117)) + "..." : trimmed
    }

    /// Converts raw proxy errors into user-friendly messages with actionable guidance
    private func userFriendlyError(from rawError: String) -> String {
        let lower = rawError.lowercased()

        // Credential errors
        if lower.contains("could not find default credentials") ||
           lower.contains("credentials") && lower.contains("not found") ||
           lower.contains("failed to create default credentials") {
            return "GCP credentials not configured. Run 'gcloud auth application-default login' in Terminal."
        }

        // Instance not found
        if lower.contains("instance not found") || lower.contains("invalid instance") {
            return "Instance not found. Check your instance connection name format (project:region:instance)."
        }

        // Project not found
        if lower.contains("project not found") {
            return "GCP project not found. Verify the project ID in your instance connection name."
        }

        // Permission errors
        if lower.contains("permission denied") || lower.contains("forbidden") ||
           lower.contains("unauthorized") || lower.contains("iam") {
            return "Permission denied. Ensure your account has Cloud SQL Client role."
        }

        // Authentication errors
        if lower.contains("authentication failed") || lower.contains("auth failed") ||
           lower.contains("token") && lower.contains("expired") {
            return "Authentication failed. Try running 'gcloud auth application-default login' again."
        }

        // Network/connection errors
        if lower.contains("connection refused") {
            return "Connection refused. Check if the Cloud SQL instance is running."
        }
        if lower.contains("connection timed out") || lower.contains("deadline exceeded") {
            return "Connection timed out. Check your network connection and firewall settings."
        }
        if lower.contains("no such host") || lower.contains("name resolution") {
            return "DNS resolution failed. Check your network connection."
        }

        // Port in use
        if lower.contains("address already in use") || lower.contains("bind") && lower.contains("use") {
            return "Port already in use. Choose a different local port."
        }

        // TLS/Certificate errors
        if lower.contains("certificate") || lower.contains("tls") || lower.contains("ssl") {
            return "TLS/certificate error. This may indicate a network proxy or firewall issue."
        }

        // API not enabled
        if lower.contains("api") && lower.contains("not enabled") ||
           lower.contains("sqladmin") && lower.contains("enabled") {
            return "Cloud SQL Admin API not enabled. Enable it in the GCP Console."
        }

        // If no specific pattern matched, return a cleaned-up version of the original
        return truncateMessage(rawError)
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
    private func waitForProxyReady(connectionId: String, port: Int, connectionName: String) {
        let startTime = Date()

        let workItem = DispatchWorkItem { [weak self] in
            self?.pollPortReadiness(
                connectionId: connectionId,
                port: port,
                startTime: startTime,
                connectionName: connectionName
            )
        }

        stateQueue.sync {
            readinessChecks[connectionId] = workItem
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    private func pollPortReadiness(
        connectionId: String,
        port: Int,
        startTime: Date,
        connectionName: String
    ) {
        // Check if we should stop polling (thread-safe read)
        let shouldContinue: Bool = stateQueue.sync {
            guard let workItem = readinessChecks[connectionId], !workItem.isCancelled else {
                return false
            }
            guard processes[connectionId]?.isRunning == true else {
                readinessChecks.removeValue(forKey: connectionId)
                return false
            }
            return true
        }

        guard shouldContinue else { return }

        // Check if we're still in connecting state (might have errored via stderr)
        // IMPORTANT: Use async dispatch to main thread to avoid potential deadlock.
        // Using sync here could deadlock if main thread is waiting on this background work.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Verify we're still in connecting state
            guard case .connecting = self.statuses[connectionId] else {
                self.stateQueue.sync {
                    self.readinessChecks.removeValue(forKey: connectionId)
                }
                return
            }

            // Continue polling work on background queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.continuePolling(
                    connectionId: connectionId,
                    port: port,
                    startTime: startTime,
                    connectionName: connectionName
                )
            }
        }
    }

    /// Continues the polling logic after confirming connection is still in connecting state.
    /// Called from background queue after main thread status check.
    private func continuePolling(
        connectionId: String,
        port: Int,
        startTime: Date,
        connectionName: String
    ) {
        // Check timeout
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed >= connectionTimeoutSeconds {
            logger.warning("Connection timeout for \(connectionName) after \(Int(elapsed))s")
            DispatchQueue.main.async { [weak self] in
                guard let self, case .connecting = self.statuses[connectionId] else { return }
                self.setStatus(.error("Connection timeout"), for: connectionId)
            }
            stateQueue.sync {
                readinessChecks.removeValue(forKey: connectionId)
            }
            return
        }

        // Try to connect to the port
        if canConnectToPort(port) {
            logger.info("Proxy ready for \(connectionName) on port \(port) after \(String(format: "%.1f", elapsed))s")
            DispatchQueue.main.async { [weak self] in
                guard let self, case .connecting = self.statuses[connectionId] else { return }
                self.setStatus(.connected, for: connectionId)
            }
            stateQueue.sync {
                readinessChecks.removeValue(forKey: connectionId)
            }
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
        let flags = fcntl(socketFD, F_GETFL, 0)
        _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Check if connected immediately
        if result == 0 {
            return true
        }

        // For non-blocking socket, EINPROGRESS means connection is being established
        if errno == EINPROGRESS {
            // Use poll instead of select for simpler API
            var pollFD = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
            let pollResult = poll(&pollFD, 1, 50) // 50ms timeout

            if pollResult > 0 && (pollFD.revents & Int16(POLLOUT)) != 0 {
                // Check if connection succeeded
                var error: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &len)
                return error == 0
            }
        }

        return false
    }

    /// Must be called while holding stateQueue lock
    private func cancelReadinessCheckUnsafe(for connectionId: String) {
        readinessChecks[connectionId]?.cancel()
        readinessChecks.removeValue(forKey: connectionId)
    }

    /// Cleans up pipe by clearing handler before removal to prevent callbacks after termination.
    /// Must be called while holding stateQueue lock.
    private func cleanupPipeUnsafe(for connectionId: String) {
        if let pipe = errorPipes[connectionId] {
            // Clear the handler first to prevent any further callbacks
            pipe.fileHandleForReading.readabilityHandler = nil
            errorPipes.removeValue(forKey: connectionId)
        }
        stderrBuffers.removeValue(forKey: connectionId)
    }

    /// Cleans up all pipes by clearing handlers before removal.
    /// Must be called while holding stateQueue lock.
    private func cleanupAllPipesUnsafe() {
        for (_, pipe) in errorPipes {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        errorPipes.removeAll()
        stderrBuffers.removeAll()
    }
}
