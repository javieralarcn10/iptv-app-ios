import SwiftUI

struct SeriesListView: View {
    @State private var store = SeriesStore.shared
    @State private var searchText = ""
    @State private var debouncedSearchText = ""

    private var searchQuery: String {
        CatalogSearch.normalizedQuery(debouncedSearchText)
    }

    private var filtered: [Series] {
        searchQuery.isEmpty ? store.series : store.series.filter {
            CatalogSearch.matches($0.name, query: searchQuery)
        }
    }

    var body: some View {
        ZStack {
            DarkBackground()
            contentBody
        }
        .navigationTitle(MediaSection.series.title)
        .searchable(text: $searchText, prompt: "Buscar")
        .task(id: searchText) {
            await debounceSearch(searchText)
        }
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
            let seriesList = filtered
            List(seriesList) { series in
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
                if seriesList.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "magnifyingglass",
                        description: Text("No hay series que coincidan con la búsqueda.")
                    )
                }
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
