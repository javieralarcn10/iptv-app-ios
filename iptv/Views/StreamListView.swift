import SwiftUI

// Handles Live TV and Movies sections
struct StreamListView: View {
    let section: MediaSection

    @State private var store = MovieStore.shared
    @State private var searchText = ""

    private var filtered: [PlayableItem] {
        searchText.isEmpty ? store.items : store.items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            DarkBackground()
            contentBody
        }
        .navigationTitle(section.title)
        .searchable(text: $searchText, prompt: "Buscar")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Label("Actualizar", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isLoading)
            }
        }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder
    private var contentBody: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView("Cargando \(section.title)...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = store.error, store.items.isEmpty {
            ErrorView(message: err) { Task { await store.refresh() } }
        } else {
            List(filtered) { item in
                NavigationLink {
                    PlayerView(item: item)
                } label: {
                    MediaRow(name: item.name, thumbnailURL: item.thumbnailURL,
                             fallbackIcon: section.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await store.refresh() }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "magnifyingglass",
                        description: Text("No hay elementos que coincidan con la búsqueda.")
                    )
                }
            }
        }
    }
}

// MARK: - Reusable subviews

struct MediaRow: View {
    let name: String
    let thumbnailURL: URL?
    let fallbackIcon: String

    var body: some View {
        HStack(spacing: 12) {
            CachedThumbnail(url: thumbnailURL, maxPixelSize: 60) {
                iconPlaceholder
            }
            .frame(width: 60, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(name)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Image(systemName: fallbackIcon)
                    .foregroundStyle(.secondary)
            )
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Reintentar", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
