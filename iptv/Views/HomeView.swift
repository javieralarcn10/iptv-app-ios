import SwiftUI

struct HomeView: View {
    @Environment(SessionManager.self) private var session
    @State private var showLogoutConfirm = false

    private let sections: [MediaSection] = [.live, .movies, .series]

    var body: some View {
        NavigationStack {
            ZStack {
                HomeAmbientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        welcomeSection
                        sectionsList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showLogoutConfirm = true
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .medium)) // reduce icon size
                            .foregroundStyle(.red)
                            .frame(width: 44, height: 44) // same button tap area as before
                    }
                }

            }
            .alert("¿Estás seguro?", isPresented: $showLogoutConfirm) {
                Button("Cerrar sesión", role: .destructive) { session.logout() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se cerrará tu sesión y tendrás que volver a iniciar sesión.")
            }
            .navigationDestination(for: MediaSection.self) { section in
                destination(for: section)
            }
        }
    }

    private var welcomeSection: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 54, height: 54)
                .glassEffect(.regular.tint(.blue.opacity(0.25)), in: .rect(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("IPTV")
                    .font(.title3.weight(.semibold))

                if let username = session.credentials?.username {
                    Text(username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            }

            Spacer(minLength: 0)
        }
    }

    private var sectionsList: some View {
        VStack(spacing: 12) {
            ForEach(sections, id: \.self) { section in
                NavigationLink(value: section) {
                    SectionGlassCard(section: section)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func destination(for section: MediaSection) -> some View {
        switch section {
        case .live:
            LiveTVView()
        case .movies:
            StreamListView(section: .movies)
        case .series:
            SeriesListView()
        }
    }
}

// MARK: - Section Card

private struct SectionGlassCard: View {
    let section: MediaSection

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: section.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(section.accentColor)
                .frame(width: 48, height: 48)
                .background(section.accentColor.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(section.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
        .glassEffect(
            .regular.tint(section.accentColor.opacity(0.1)),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
    }
}

// MARK: - Background

private struct HomeAmbientBackground: View {
    var body: some View {
        ZStack {
            DarkBackground()

            Circle()
                .fill(Color.red.opacity(0.22))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -130, y: -300)

            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: 150, y: -80)

            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -90, y: 340)
        }
    }
}

// MARK: - Section Metadata

private extension MediaSection {
    var subtitle: String {
        switch self {
        case .live: return "Canales en directo"
        case .movies: return "Películas bajo demanda"
        case .series: return "Series y episodios"
        }
    }

    var accentColor: Color {
        switch self {
        case .live: return .red
        case .movies: return .purple
        case .series: return .cyan
        }
    }
}
