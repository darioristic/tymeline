import SwiftUI
import TymelineCore

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            WorkspacesTab(coordinator: coordinator)
                .tabItem { Label("Workspaces", systemImage: "folder.badge.plus") }

            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
    }
}

private struct WorkspacesTab: View {
    let coordinator: AppCoordinator

    @State private var name: String = ""
    @State private var linearKey: String = ""
    @State private var clockifyKey: String = ""
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workspaces").font(.title2)

            if coordinator.snapshots.isEmpty {
                Text("No workspaces yet. Add one below.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.snapshots, id: \.workspaceId) { snapshot in
                    WorkspaceRow(snapshot: snapshot)
                }
            }

            Divider()

            Text("Add workspace").font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Work"))
                SecureField("Linear API key", text: $linearKey)
                SecureField("Clockify API key", text: $clockifyKey)
            }

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || linearKey.isEmpty || clockifyKey.isEmpty || isConnecting)

                if isConnecting {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        let nameValue = name
        let linearValue = linearKey
        let clockifyValue = clockifyKey
        Task { @MainActor in
            do {
                try await coordinator.addWorkspace(
                    name: nameValue,
                    linearKey: linearValue,
                    clockifyKey: clockifyValue
                )
                name = ""
                linearKey = ""
                clockifyKey = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

private struct WorkspaceRow: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Text(snapshot.workspaceName).bold()
            statusLabel
            Spacer()
            if let pollAt = snapshot.lastPollAt {
                Text(pollAt, format: .dateTime.hour().minute().second())
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let identifier = snapshot.runningIssueIdentifier,
           let title = snapshot.runningIssueTitle {
            Text("• \(identifier) \(title)")
                .foregroundStyle(.green)
        } else if let err = snapshot.lastErrorDescription {
            Text("• \(err)")
                .foregroundStyle(.red)
                .lineLimit(1)
        } else {
            Text("• idle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct GeneralTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.title2)
            Text("Behavior preferences will live here (auto-start, idle threshold, notifications).")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tymeline").font(.title)
            Text("Open-source macOS menubar app that syncs Linear issue status to Clockify timers.")
            Text("Version 0.1.0").foregroundStyle(.secondary)
            Link(
                "github.com/darioristic/tymeline",
                destination: URL(string: "https://github.com/darioristic/tymeline")!
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
