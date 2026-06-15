import SwiftUI

struct SeriesListView: View {
    @State private var store = SeriesStore.shared
    @State private var searchText = ""

    private var filtered: [Series] {
        searchText.isEmpty ? store.series : store.series.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            DarkBackground()
            contentBody
        }
        .navigationTitle(MediaSection.series.title)
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
        if store.isLoading && store.series.isEmpty {
            ProgressView("Cargando Series...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = store.error, store.series.isEmpty {
            ErrorView(message: err) { Task { await store.refresh() } }
        } else {
            List(filtered) { series in
                NavigationLink {
                    SeriesDetailView(series: series)
                } label: {
                    MediaRow(
                        name: series.name,
                        thumbnailURL: series.cover.flatMap { URL(string: $0) },
                        fallbackIcon: MediaSection.series.systemImage
                    )
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
                        description: Text("No hay series que coincidan con la búsqueda.")
                    )
                }
            }
        }
    }
}
