import SwiftUI
import TymelineCore

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            WorkspacesTab(coordinator: coordinator)
                .tabItem { Label("Workspaces", systemImage: "folder.badge.plus") }

            ProjectsTab(coordinator: coordinator)
                .tabItem { Label("Projects", systemImage: "rectangle.connected.to.line.below") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 680, minHeight: 520)
    }
}

private struct TabPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    func tabPadding() -> some View { modifier(TabPadding()) }
}

private struct WorkspacesTab: View {
    let coordinator: AppCoordinator

    @State private var name: String = ""
    @State private var linearKey: String = ""
    @State private var clockifyKey: String = ""
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?
    @State private var connectedAt: Date?
    @State private var connectedName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Workspaces").font(.title2)

                if coordinator.snapshots.isEmpty {
                    GroupBox {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No workspaces yet. Add one below to start tracking time.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                } else {
                    ForEach(coordinator.snapshots, id: \.workspaceId) { snapshot in
                        WorkspaceCard(snapshot: snapshot, coordinator: coordinator)
                    }
                }

                Divider().padding(.vertical, 4)

                GroupBox(label: Text("Add workspace").font(.headline).padding(.bottom, 4)) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Name", text: $name, prompt: Text("e.g. Work"))

                            SecureField("Linear API key", text: $linearKey)
                            keyHint(
                                "Get key at",
                                linkTitle: "linear.app/settings/api",
                                url: "https://linear.app/settings/api"
                            )

                            SecureField("Clockify API key", text: $clockifyKey)
                            keyHint(
                                "Get key at",
                                linkTitle: "app.clockify.me/user/settings",
                                url: "https://app.clockify.me/user/settings"
                            )
                        }

                        if let err = errorMessage {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }

                        HStack {
                            Button("Connect") { connect() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(name.isEmpty || linearKey.isEmpty || clockifyKey.isEmpty || isConnecting)
                            if isConnecting {
                                ProgressView().controlSize(.small)
                            }
                            if let connectedAt, let connectedName {
                                Label("Connected to \(connectedName) at \(connectedAt.formatted(date: .omitted, time: .standard))", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.callout)
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                }
            }
        }
        .tabPadding()
    }

    @ViewBuilder
    private func keyHint(_ prefix: String, linkTitle: String, url: String) -> some View {
        HStack(spacing: 4) {
            Text(prefix)
                .foregroundStyle(.tertiary)
                .font(.caption)
            Link(linkTitle, destination: URL(string: url)!)
                .font(.caption)
            Spacer()
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        connectedAt = nil
        connectedName = nil
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
                connectedName = nameValue
                connectedAt = Date()
                name = ""
                linearKey = ""
                clockifyKey = ""
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if connectedName == nameValue {
                    connectedAt = nil
                    connectedName = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

private struct WorkspaceCard: View {
    let snapshot: WorkspaceSnapshot
    let coordinator: AppCoordinator

    @State private var showRemoveConfirm = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusDot
                    Text(snapshot.workspaceName).font(.headline)
                    statusBadge
                    Spacer()
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove workspace")
                }

                if let identifier = snapshot.runningIssueIdentifier,
                   let title = snapshot.runningIssueTitle {
                    Label("Running: \(identifier) — \(title)", systemImage: "play.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                        .lineLimit(1)
                }

                if let err = snapshot.lastErrorDescription {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .lineLimit(2)
                }

                HStack(spacing: 16) {
                    metric(
                        icon: "list.bullet",
                        label: issuesLabel
                    )
                    metric(
                        icon: "rectangle.connected.to.line.below",
                        label: projectsLabel
                    )
                }
                .font(.caption)

                Toggle(isOn: includeBacklogBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include backlog issues")
                            .font(.callout)
                        Text("Show issues in 'Backlog' state in the menubar list, not just Todo/In Progress.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .confirmationDialog(
            "Remove workspace '\(snapshot.workspaceName)'?",
            isPresented: $showRemoveConfirm
        ) {
            Button("Remove", role: .destructive) {
                Task { @MainActor in
                    await coordinator.removeWorkspace(workspaceId: snapshot.workspaceId)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the workspace configuration and API keys from your Keychain. Existing Clockify entries are not affected.")
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if snapshot.runningIssueId != nil {
            Circle().fill(.green).frame(width: 8, height: 8)
        } else if snapshot.lastErrorDescription != nil {
            Circle().fill(.red).frame(width: 8, height: 8)
        } else if snapshot.lastPollAt != nil {
            Circle().fill(.blue).frame(width: 8, height: 8)
        } else {
            Circle().fill(.gray).frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if snapshot.runningIssueId != nil {
            Text("running").font(.caption).foregroundStyle(.green)
        } else if snapshot.lastErrorDescription != nil {
            Text("error").font(.caption).foregroundStyle(.red)
        } else if snapshot.lastPollAt != nil {
            Text("connected").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("connecting...").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var issuesLabel: String {
        let n = snapshot.assignedIssues.count
        return "\(n) assigned issue\(n == 1 ? "" : "s")"
    }

    private var projectsLabel: String {
        let mappings = coordinator.workspaceMappings[snapshot.workspaceId] ?? [:]
        let configured = mappings.values.filter { !$0.isEmpty }.count
        let referenced = Set(snapshot.assignedIssues.compactMap(\.projectId)).count
        if referenced == 0 {
            return "\(configured) project\(configured == 1 ? "" : "s") mapped"
        }
        let covered = Set(snapshot.assignedIssues.compactMap(\.projectId))
            .filter { mappings[$0]?.isEmpty == false }
            .count
        return "\(covered) of \(referenced) needed project\(referenced == 1 ? "" : "s") mapped"
    }

    @ViewBuilder
    private func metric(icon: String, label: String) -> some View {
        Label(label, systemImage: icon).foregroundStyle(.secondary)
    }

    private var includeBacklogBinding: Binding<Bool> {
        Binding(
            get: { snapshot.includeBacklog },
            set: { newValue in
                Task { @MainActor in
                    await coordinator.setIncludeBacklog(
                        workspaceId: snapshot.workspaceId,
                        value: newValue
                    )
                }
            }
        )
    }
}

private struct ProjectsTab: View {
    let coordinator: AppCoordinator

    @State private var selectedWorkspaceId: UUID?
    @State private var draftMappings: [String: String] = [:]
    @State private var isSaving: Bool = false
    @State private var savedAt: Date?
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Project mappings").font(.title2)
            Text("Map each Linear project to the Clockify project that timers should be logged under.")
                .foregroundStyle(.secondary)
                .font(.callout)

            if coordinator.snapshots.isEmpty {
                Text("Add a workspace first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                workspacePicker
                if let workspaceId = selectedWorkspaceId {
                    mappingsList(for: workspaceId)
                }
            }

            Spacer()
        }
        .tabPadding()
        .task(id: selectedWorkspaceId) {
            if let id = selectedWorkspaceId {
                await loadFor(workspaceId: id)
            }
        }
        .onAppear {
            if selectedWorkspaceId == nil {
                selectedWorkspaceId = coordinator.snapshots.first?.workspaceId
            }
        }
    }

    @ViewBuilder
    private var workspacePicker: some View {
        Picker("Workspace", selection: $selectedWorkspaceId) {
            ForEach(coordinator.snapshots, id: \.workspaceId) { snapshot in
                Text(snapshot.workspaceName).tag(Optional(snapshot.workspaceId))
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func mappingsList(for workspaceId: UUID) -> some View {
        if let err = coordinator.projectsError[workspaceId] {
            Text(err).foregroundStyle(.red).font(.callout)
        }

        if let projects = coordinator.workspaceProjects[workspaceId] {
            if projects.linear.isEmpty {
                Text("No Linear projects found.").foregroundStyle(.secondary)
            } else {
                let referenced = referencedProjectIds(for: workspaceId)
                let unmappedReferencedCount = projects.linear
                    .filter { referenced.contains($0.id) && (draftMappings[$0.id] ?? "").isEmpty }
                    .count

                if unmappedReferencedCount > 0 {
                    Label(
                        "\(unmappedReferencedCount) project\(unmappedReferencedCount == 1 ? "" : "s") with assigned issues need mapping",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(projects.linear) { linearProject in
                            mappingRow(
                                linearProject: linearProject,
                                clockifyProjects: projects.clockify,
                                needsMapping: referenced.contains(linearProject.id)
                                    && (draftMappings[linearProject.id] ?? "").isEmpty
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)

                HStack {
                    Button(isSaving ? "Saving..." : "Save mappings") {
                        save(workspaceId: workspaceId)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)

                    Button("Auto-match by name") {
                        autoMatchByName(workspaceId: workspaceId)
                    }
                    .help("Pre-fill mappings for Linear projects whose name exactly matches a Clockify project (does not overwrite existing mappings)")

                    Button("Refresh project lists") {
                        Task { await loadFor(workspaceId: workspaceId) }
                    }

                    if let savedAt {
                        Label("Saved at \(savedAt.formatted(date: .omitted, time: .standard))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else if let err = saveError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
        } else {
            ProgressView("Loading projects...")
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func mappingRow(
        linearProject: LinearProject,
        clockifyProjects: [ClockifyProject],
        needsMapping: Bool
    ) -> some View {
        HStack {
            if needsMapping {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .help("Linear project has assigned issues but no Clockify mapping")
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.clear)
                    .font(.caption)
            }

            Text(linearProject.name)
                .frame(width: 200, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Picker(
                "",
                selection: Binding(
                    get: { draftMappings[linearProject.id] ?? "" },
                    set: { draftMappings[linearProject.id] = $0 }
                )
            ) {
                Text("(none)").tag("")
                ForEach(clockifyProjects) { clockifyProject in
                    Text(clockifyProject.name + (clockifyProject.clientName.map { " - \($0)" } ?? ""))
                        .tag(clockifyProject.id)
                }
            }
            .labelsHidden()
        }
    }

    private func referencedProjectIds(for workspaceId: UUID) -> Set<String> {
        guard let snapshot = coordinator.snapshots.first(where: { $0.workspaceId == workspaceId }) else {
            return []
        }
        return Set(snapshot.assignedIssues.compactMap(\.projectId))
    }

    /// Pre-fills draftMappings for any Linear project whose normalized name
    /// (lowercased + trimmed) matches a Clockify project. Doesn't overwrite
    /// existing user-chosen mappings - this is a starter, not a steamroller.
    private func autoMatchByName(workspaceId: UUID) {
        guard let projects = coordinator.workspaceProjects[workspaceId] else { return }
        let clockifyByName = Dictionary(
            grouping: projects.clockify,
            by: { Self.normalize($0.name) }
        ).compactMapValues { $0.first }

        var matched = 0
        for linearProject in projects.linear {
            let current = draftMappings[linearProject.id] ?? ""
            if !current.isEmpty { continue }
            if let match = clockifyByName[Self.normalize(linearProject.name)] {
                draftMappings[linearProject.id] = match.id
                matched += 1
            }
        }

        if matched > 0 {
            saveError = nil
            savedAt = nil
        }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadFor(workspaceId: UUID) async {
        await coordinator.loadProjects(for: workspaceId)
        draftMappings = coordinator.workspaceMappings[workspaceId] ?? [:]
    }

    private func save(workspaceId: UUID) {
        isSaving = true
        savedAt = nil
        saveError = nil
        let mappings = draftMappings.filter { !$0.value.isEmpty }
        Task { @MainActor in
            await coordinator.setProjectMappings(workspaceId: workspaceId, mappings: mappings)
            isSaving = false
            if let err = coordinator.actionError {
                saveError = err
            } else {
                savedAt = Date()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if savedAt != nil {
                    savedAt = nil
                }
            }
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("tymeline").font(.title)
            Text("Open-source macOS menubar app that syncs Linear issue status to Clockify timers.")
                .foregroundStyle(.secondary)
            Text("Version 0.1.0").foregroundStyle(.tertiary).font(.callout)
            Link(
                "github.com/darioristic/tymeline",
                destination: URL(string: "https://github.com/darioristic/tymeline")!
            )
            Spacer()
        }
        .tabPadding()
    }
}
