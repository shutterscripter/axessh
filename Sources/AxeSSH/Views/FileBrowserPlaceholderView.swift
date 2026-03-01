import SwiftUI

struct FileBrowserPlaceholderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let profile = appState.selectedProfile {
                Text("SFTP Browser")
                    .font(.title3.weight(.semibold))
                Text("Connection: \(profile.connectionName)")
                Text("Host: \(profile.username)@\(profile.server):\(profile.port)")
                    .foregroundStyle(.secondary)
            } else {
                Text("No connection selected")
            }

            Divider()
            Text("Phase 1 placeholder. SFTP browse/upload/download will be implemented in Phase 3.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 360)
    }
}
