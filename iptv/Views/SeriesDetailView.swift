import SwiftUI

struct SeriesDetailView: View {
    let series: Series

    @State private var seasons: [SeasonSection] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var hasLoaded = false

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
                ForEach(seasons) { season in
                    Section("Temporada \(season.number)") {
                        ForEach(season.episodes) { playableEpisode in
                            NavigationLink {
                                PlayerView(item: playableEpisode.item)
                            } label: {
                                EpisodeRow(episode: playableEpisode.episode)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .listRowBackground(Color.clear)
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
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        error = nil
        do {
            let loadedResponse = try await XtreamAPIService.shared.getSeriesInfo(seriesId: series.seriesId)
            seasons = seasonSections(from: loadedResponse)
            hasLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func seasonSections(from response: SeriesInfoResponse) -> [SeasonSection] {
        guard let episodes = response.episodes else { return [] }
        return episodes.keys
            .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            .compactMap { key in
                guard let list = episodes[key] else { return nil }
                let playableEpisodes = list.compactMap { episode -> PlayableEpisode? in
                    guard let item = playableItem(from: episode) else { return nil }
                    return PlayableEpisode(episode: episode, item: item)
                }
                guard !playableEpisodes.isEmpty else { return nil }
                return SeasonSection(number: key, episodes: playableEpisodes)
            }
    }
}

private struct SeasonSection: Identifiable {
    let number: String
    let episodes: [PlayableEpisode]

    var id: String { number }
}

private struct PlayableEpisode: Identifiable {
    let episode: Episode
    let item: PlayableItem

    var id: String { episode.id }
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
