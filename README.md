# PortLight

A macOS menu bar app for managing Cloud SQL Proxy connections.

## Features

- Menu bar interface for quick connection management
- Support for multiple database connections
- Auto-connect on launch option
- Real-time connection status monitoring

## Requirements

- macOS 14.0+
- [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/mysql/sql-proxy) binary installed
- GCP credentials configured (`gcloud auth application-default login`)

## Installation

1. Download the latest release
2. Move PortLight.app to your Applications folder
3. Launch PortLight from Applications

## Configuration

On first launch, configure the path to your `cloud-sql-proxy` binary in the "Manage Connections" window.

## Security Considerations

### App Sandbox Disabled

PortLight has **App Sandbox disabled** (`ENABLE_APP_SANDBOX = NO`). This is a necessary trade-off for the app's core functionality:

1. **Process Execution**: The app must execute the `cloud-sql-proxy` binary, which requires spawning external processes
2. **Network Management**: Managing proxy connections requires low-level network socket operations
3. **File System Access**: The app needs to access the proxy binary from user-specified paths

**Mitigations in place:**

- **Hardened Runtime**: The app uses Hardened Runtime for code signing, providing additional security protections
- **No Network Access**: PortLight itself does not make network requests; all networking is handled by the cloud-sql-proxy binary
- **Local Only**: The app only manages local proxy instances and does not transmit any data

### Credential Handling

PortLight does not store or handle GCP credentials directly. It relies on the standard `gcloud` application-default credentials flow.

## License

MIT License
