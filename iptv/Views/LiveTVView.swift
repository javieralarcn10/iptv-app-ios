import SwiftUI

struct LiveTVView: View {
    @State private var playlist = LivePlaylistStore.shared
    @State private var searchText = ""

    private var filteredStreams: [LiveStream] {
        guard !searchText.isEmpty else { return [] }
        return playlist.streams.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            DarkBackground()

            content
        }
        .navigationTitle("Live TV")
        .searchable(text: $searchText, prompt: "Buscar canal")
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
        } else if !searchText.isEmpty {
            channelList(filteredStreams)
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
        List(Array(streams.enumerated()), id: \.offset) { _, stream in
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

}

struct LiveCategoryChannelsView: View {
    let title: String
    var categoryId: String?
    @Binding var searchText: String

    @State private var playlist = LivePlaylistStore.shared

    private var visibleStreams: [LiveStream] {
        if !searchText.isEmpty {
            return playlist.streams.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        guard let categoryId else { return playlist.streams }
        return playlist.streams.filter { $0.categoryId == categoryId }
    }

    var body: some View {
        ZStack {
            DarkBackground()

            List(Array(visibleStreams.enumerated()), id: \.offset) { _, stream in
                LiveChannelNavigationLink(stream: stream)
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if visibleStreams.isEmpty {
                    ContentUnavailableView(
                        "Sin canales",
                        systemImage: "tv.slash",
                        description: Text("No hay canales para mostrar.")
                    )
                }
            }
        }
        .navigationTitle(searchText.isEmpty ? title : "Resultados")
        .searchable(text: $searchText, prompt: "Buscar canal")
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
