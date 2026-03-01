import SwiftUI

struct ConnectionCardView: View {
    let profile: SSHProfile
    let onEdit: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onBrowse: () -> Void

    private let cardBackground = Color(white: 0.20)

    var body: some View {
        HStack(spacing: 0) {
            // Left: connection name + status (tappable when connected to disconnect)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.connectionName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(profile.status.label)
                    .font(.caption)
                    .foregroundStyle(profile.status == .connected ? Color.green : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if profile.status == .connected {
                    onDisconnect()
                } else {
                    onConnect()
                }
            }

            // Right: three square icon buttons (terminal icon opens Terminal + SSH)
            HStack(spacing: -10) {
                IconButton(systemName: "square.and.pencil.circle.fill", size: 42, action: onEdit)
                IconButton(systemName: "apple.terminal.circle.fill", size: 42, action: onConnect)
                IconButton(systemName: "document.circle.fill", size: 42, action: onBrowse)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      
    }
}

private struct IconButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size)
                .background(Color.clear)
                
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConnectionCardView(
        profile: SSHProfile(
            connectionName: "My Server",
            server: "host.example.com",
            username: "user",
            status: .disconnected
        ),
        onEdit: {},
        onConnect: {},
        onDisconnect: {},
        onBrowse: {}
    )
    .padding()
    .background(Color.black)
}
