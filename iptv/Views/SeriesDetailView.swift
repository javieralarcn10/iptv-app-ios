import SwiftUI

struct SeriesDetailView: View {
    let series: Series

    @State private var response: SeriesInfoResponse?
    @State private var isLoading = false
    @State private var error: String?

    private var seasons: [(number: String, episodes: [Episode])] {
        guard let eps = response?.episodes else { return [] }
        return eps.keys
            .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            .compactMap { key in
                guard let list = eps[key], !list.isEmpty else { return nil }
                return (number: key, episodes: list)
            }
    }

    var body: some View {
        ZStack {
            DarkBackground()
            contentBody
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadContent() }
    }

    @ViewBuilder
    private var contentBody: some View {
        if isLoading {
            ProgressView("Cargando episodios...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = error {
            ErrorView(message: err) { Task { await loadContent() } }
        } else if seasons.isEmpty {
            ContentUnavailableView(
                "Sin episodios",
                systemImage: "tv.slash",
                description: Text("No se encontraron episodios para esta serie.")
            )
        } else {
            List {
                ForEach(seasons, id: \.number) { season in
                    Section("Temporada \(season.number)") {
                        ForEach(season.episodes) { episode in
                            if let item = playableItem(from: episode) {
                                NavigationLink {
                                    PlayerView(item: item)
                                } label: {
                                    EpisodeRow(episode: episode)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func playableItem(from episode: Episode) -> PlayableItem? {
        guard let ext = episode.containerExtension,
              let url = try? XtreamAPIService.shared.episodeURL(
                  episodeId: episode.id, ext: ext)
        else { return nil }
        let epNum = episode.episodeNum.map { "E\($0) " } ?? ""
        let title = episode.title ?? ""
        return PlayableItem(
            id: Int(episode.id) ?? 0,
            name: "\(epNum)\(title)".trimmingCharacters(in: .whitespaces),
            url: url,
            thumbnailURL: nil
        )
    }

    private func loadContent() async {
        isLoading = true
        error = nil
        do {
            response = try await XtreamAPIService.shared.getSeriesInfo(seriesId: series.seriesId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            if let num = episode.episodeNum {
                Text("\(num)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title ?? "Episodio \(episode.episodeNum ?? 0)")
                    .foregroundStyle(.primary)
                if let ext = episode.containerExtension {
                    Text(ext.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
