import SwiftUI
import AppKit

struct AboutView: View {
    private let sourceCodeURL = URL(string: "https://github.com/shutterscripter/axessh")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AxeSSH")
                .font(.title2.weight(.semibold))

            Text("A lightweight macOS menu bar app to manage SSH connections, open terminal sessions quickly, and browse remote files over SFTP.")
                .foregroundStyle(.secondary)


            Divider()

            HStack {
                Image(systemName: "globe")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                Link("GitHub Repository", destination: sourceCodeURL)
            }


        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 170)
        .background(
            AboutWindowAccessor { window in
                guard let window else { return }
                window.level = .normal
                Task { @MainActor in bringAboutWindowToFront(window) }
                for delay in [0.2, 0.5] as [Double] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Task { @MainActor in bringAboutWindowToFront(window) }
                    }
                }
            }
        )
        .onAppear {
            Task { @MainActor in
                NSApp.setActivationPolicy(.regular)
            }
        }
        .onDisappear {
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@MainActor
private func bringAboutWindowToFront(_ window: NSWindow) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

private struct AboutWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        tryResolveWindow(view: view, coordinator: context.coordinator)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            tryResolveWindow(view: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        tryResolveWindow(view: nsView, coordinator: context.coordinator)
    }

    private func tryResolveWindow(view: NSView, coordinator: Coordinator) {
        guard let window = view.window, !coordinator.didResolve else { return }
        coordinator.didResolve = true
        window.title = "About"
        onResolve(window)
    }

    final class Coordinator {
        var didResolve = false
    }
}

