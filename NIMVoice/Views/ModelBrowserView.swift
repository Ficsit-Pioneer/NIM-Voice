import SwiftUI

/// Browses the live NVIDIA model catalog (`GET /v1/models`). Supports search,
/// category grouping, favorites, selection (persisted as the active model), and
/// pull-to-refresh. Handles loading / empty / error states gracefully.
struct ModelBrowserView: View {
    @Environment(VoiceSessionViewModel.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var models: [NIMModel] = []
    @State private var searchText = ""
    @State private var phase: LoadPhase = .loading

    private enum LoadPhase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading where models.isEmpty:
                    ProgressView("Loading catalog…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let message) where models.isEmpty:
                    errorState(message)
                case .empty:
                    emptyState
                default:
                    modelList
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
        }
        .task { await load() }
    }

    // MARK: - List

    private var modelList: some View {
        List {
            // Active model, shown prominently at the top.
            Section {
                activeRow
            }

            if !favoriteModels.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteModels) { model in row(for: model) }
                }
            }

            ForEach(groupedCategories, id: \.self) { category in
                Section {
                    ForEach(grouped[category] ?? []) { model in row(for: model) }
                } header: {
                    Label(category.rawValue, systemImage: category.symbol)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(force: true) }
        .overlay(alignment: .bottom) {
            if case .error(let message) = phase, !models.isEmpty {
                inlineErrorBar(message)
            }
        }
    }

    private var activeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Active model").font(.caption).foregroundStyle(.secondary)
                Text(session.activeModelID)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func row(for model: NIMModel) -> some View {
        Button {
            select(model)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let vendor = model.vendor {
                        Text(vendor).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    settings.toggleFavorite(model.id)
                    Haptics.tap()
                } label: {
                    Image(systemName: settings.isFavorite(model.id) ? "star.fill" : "star")
                        .foregroundStyle(settings.isFavorite(model.id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                if model.id == session.activeModelID {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load models", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await load(force: true) } }
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No models found", systemImage: "tray")
        } description: {
            Text("The catalog returned no models. Pull to refresh.")
        }
    }

    private func inlineErrorBar(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.bottom, 8)
    }

    // MARK: - Filtering / grouping

    private var filteredModels: [NIMModel] {
        guard !searchText.isEmpty else { return models }
        return models.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
    }

    private var favoriteModels: [NIMModel] {
        filteredModels.filter { settings.isFavorite($0.id) }
    }

    private var grouped: [ModelCategory: [NIMModel]] {
        Dictionary(grouping: filteredModels.filter { !settings.isFavorite($0.id) }, by: \.category)
    }

    private var groupedCategories: [ModelCategory] {
        ModelCategory.allCases.filter { !(grouped[$0]?.isEmpty ?? true) }
    }

    // MARK: - Actions

    private func select(_ model: NIMModel) {
        session.setActiveModel(model.id)
        Haptics.success()
        dismiss()
    }

    private func load(force: Bool = false) async {
        if !force, !models.isEmpty { return }
        if models.isEmpty { phase = .loading }

        guard let key = KeychainStore.read(), !key.isEmpty else {
            phase = .error("Add your NVIDIA API key in Settings first.")
            return
        }

        do {
            let fetched = try await NIMClient.shared.listModels(apiKey: key)
            models = fetched
            phase = fetched.isEmpty ? .empty : .loaded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .error(message)
        }
    }
}
