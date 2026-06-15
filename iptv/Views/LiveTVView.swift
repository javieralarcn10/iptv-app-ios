import SwiftUI

struct LiveTVView: View {
    @State private var playlist = LivePlaylistStore.shared
    @State private var searchText = ""
    @State private var debouncedSearchText = ""

    private var searchQuery: String {
        CatalogSearch.normalizedQuery(debouncedSearchText)
    }

    private var filteredStreams: [LiveStream] {
        guard !searchQuery.isEmpty else { return [] }
        return playlist.streams.filter { CatalogSearch.matches($0.name, query: searchQuery) }
    }

    var body: some View {
        ZStack {
            DarkBackground()

            content
        }
        .navigationTitle("Live TV")
        .searchable(text: $searchText, prompt: "Buscar canal")
        .task(id: searchText) {
            await debounceSearch(searchText)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await playlist.refresh() }
                } label: {
                    if playlist.isLoading {
                        ProgressView()
                    } else {
                        Label("Actualizar playlist", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(playlist.isLoading)
            }
        }
        .task { await playlist.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if playlist.isLoading && playlist.streams.isEmpty {
            ProgressView("Cargando Live TV...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = playlist.error, playlist.streams.isEmpty {
            ErrorView(message: err) { Task { await playlist.refresh() } }
        } else if !searchQuery.isEmpty {
            let streams = filteredStreams
            channelList(streams)
        } else {
            categoryList
        }
    }

    private var categoryList: some View {
        let counts = playlist.streamCountByCategory
        return List {
            Section {
                NavigationLink {
                    LiveCategoryChannelsView(
                        title: "Todos los canales",
                        searchText: $searchText
                    )
                } label: {
                    CategoryRow(
                        title: "Todos los canales",
                        count: playlist.streams.count,
                        systemImage: "rectangle.grid.2x2.fill"
                    )
                }

                ForEach(playlist.categories) { category in
                    NavigationLink {
                        LiveCategoryChannelsView(
                            title: category.categoryName,
                            categoryId: category.categoryId,
                            searchText: $searchText
                        )
                    } label: {
                        CategoryRow(
                            title: category.categoryName,
                            count: counts[category.categoryId] ?? 0,
                            systemImage: "folder.fill"
                        )
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func channelList(_ streams: [LiveStream]) -> some View {
        List(streams) { stream in
            LiveChannelNavigationLink(stream: stream)
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if streams.isEmpty {
                ContentUnavailableView(
                    "Sin resultados",
                    systemImage: "magnifyingglass",
                    description: Text("No hay canales que coincidan con la búsqueda.")
                )
            }
        }
    }

    private func debounceSearch(_ text: String) async {
        let query = CatalogSearch.normalizedQuery(text)
        guard !query.isEmpty else {
            debouncedSearchText = ""
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(180))
        } catch {
            return
        }
        debouncedSearchText = query
    }

}

struct LiveCategoryChannelsView: View {
    let title: String
    var categoryId: String?
    @Binding var searchText: String

    @State private var playlist = LivePlaylistStore.shared
    @State private var debouncedSearchText = ""

    private var searchQuery: String {
        CatalogSearch.normalizedQuery(debouncedSearchText)
    }

    private var visibleStreams: [LiveStream] {
        if !searchQuery.isEmpty {
            return playlist.streams.filter { CatalogSearch.matches($0.name, query: searchQuery) }
        }
        return playlist.streams(for: categoryId)
    }

    var body: some View {
        ZStack {
            DarkBackground()

            let streams = visibleStreams
            List(streams) { stream in
                LiveChannelNavigationLink(stream: stream)
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if streams.isEmpty {
                    ContentUnavailableView(
                        "Sin canales",
                        systemImage: "tv.slash",
                        description: Text("No hay canales para mostrar.")
                    )
                }
            }
        }
        .navigationTitle(searchQuery.isEmpty ? title : "Resultados")
        .searchable(text: $searchText, prompt: "Buscar canal")
        .task(id: searchText) {
            await debounceSearch(searchText)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await playlist.refresh() }
                } label: {
                    if playlist.isLoading {
                        ProgressView()
                    } else {
                        Label("Actualizar playlist", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(playlist.isLoading)
            }
        }
    }

    private func debounceSearch(_ text: String) async {
        let query = CatalogSearch.normalizedQuery(text)
        guard !query.isEmpty else {
            debouncedSearchText = ""
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(180))
        } catch {
            return
        }
        debouncedSearchText = query
    }
}

private struct LiveChannelNavigationLink: View {
    let stream: LiveStream

    var body: some View {
        NavigationLink {
            if let item = playableItem {
                PlayerView(item: item)
            } else {
                ContentUnavailableView(
                    "No se puede abrir el canal",
                    systemImage: "tv.slash",
                    description: Text("La URL del canal no es válida.")
                )
            }
        } label: {
            MediaRow(
                name: stream.name,
                thumbnailURL: stream.streamIcon.flatMap { URL(string: $0) },
                fallbackIcon: MediaSection.live.systemImage
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }

    }

    private var playableItem: PlayableItem? {
        guard let url = try? XtreamAPIService.shared.liveURL(for: stream) else { return nil }
        return PlayableItem(
            id: stream.streamId,
            name: stream.name,
            url: url,
            thumbnailURL: stream.streamIcon.flatMap { URL(string: $0) },
            isLive: true
        )
    }
}

private struct CategoryRow: View {
    let title: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(count) canales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DarkBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.04, blue: 0.07),
                Color(red: 0.00, green: 0.00, blue: 0.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
