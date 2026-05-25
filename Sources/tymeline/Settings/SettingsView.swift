import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            WorkspacesTab()
                .tabItem { Label("Workspaces", systemImage: "folder.badge.plus") }

            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
    }
}

private struct WorkspacesTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workspaces").font(.title2)
            Text("No workspaces configured yet.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

#Preview {
    SettingsView()
}
