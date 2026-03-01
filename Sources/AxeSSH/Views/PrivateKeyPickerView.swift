import SwiftUI
import AppKit

struct PrivateKeyPickerView: View {
    @Binding var selection: String
    let recentPaths: [String]
    let onAddRecent: (String) -> Void

    private var displayLabel: String {
        if selection.isEmpty { return "None" }
        return selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SSH Private Key")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("None") {
                    selection = ""
                }

                if !recentPaths.isEmpty {
                    Divider()
                    ForEach(recentPaths, id: \.self) { path in
                        Button(path) {
                            selection = path
                        }
                    }
                }

                Divider()
                Button {
                    openFilePanel()
                } label: {
                    Label("Choose...", systemImage: "folder.badge.plus")
                }
            } label: {
                HStack(spacing: 6 ) {
                    Text(displayLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                  
                    
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }


        }
    } 

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Select SSH Private Key"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        selection = path
        onAddRecent(path)
    }
}
