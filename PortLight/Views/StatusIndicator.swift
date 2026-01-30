import SwiftUI

struct StatusIndicator: View {
    let status: ConnectionStatus

    @State private var isAnimating = false
    @State private var errorPulse = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 10, height: 10)
            .opacity(opacity)
            .scaleEffect(scale)
            .onChange(of: status) { _, newValue in
                updateAnimation(for: newValue)
                if case .error = newValue {
                    withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)) {
                        errorPulse.toggle()
                    }
                }
            }
            .onAppear {
                updateAnimation(for: status)
            }
            // Use single animation modifier for the connecting pulse
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
    }

    private var opacity: Double {
        if case .connecting = status {
            return isAnimating ? 0.4 : 1.0
        }
        return 1.0
    }

    private var scale: CGFloat {
        if case .error = status {
            return errorPulse ? 1.3 : 1.0
        }
        return 1.0
    }

    private func updateAnimation(for status: ConnectionStatus) {
        // Use `if case` pattern matching consistently for all status checks.
        // This is more future-proof if associated values are added to other cases.
        if case .connecting = status {
            isAnimating = true
        } else {
            isAnimating = false
        }
    }
}
