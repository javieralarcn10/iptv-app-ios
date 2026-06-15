import SwiftUI

// Defined at file scope so both LoginView and LoginGlassField can reference it
fileprivate enum LoginField: Hashable {
    case serverURL, username, password
}

struct LoginView: View {
    @Environment(SessionManager.self) private var session

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: LoginField?

    private var canConnect: Bool {
        !serverURL.trimmed.isEmpty &&
        !username.trimmed.isEmpty &&
        !password.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LoginAmbientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("Iniciar sesión")
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 16)

                        heroSection
                        formSection

                        if let error = errorMessage {
                            errorBanner(error)
                        }

                        connectButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var heroSection: some View {
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

                Text("Conecta tu servidor para empezar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var formSection: some View {
        VStack(spacing: 12) {
            LoginGlassField(
                placeholder: "URL del servidor",
                text: $serverURL,
                keyboardType: .URL,
                field: .serverURL,
                focusedField: $focusedField,
                submitLabel: .next
            ) {
                focusedField = .username
            }

            LoginGlassField(
                placeholder: "Usuario",
                text: $username,
                field: .username,
                focusedField: $focusedField,
                submitLabel: .next
            ) {
                focusedField = .password
            }

            LoginGlassField(
                placeholder: "Contraseña",
                text: $password,
                isSecure: true,
                field: .password,
                focusedField: $focusedField,
                submitLabel: .go
            ) {
                attemptLogin()
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(
            .regular.tint(.red.opacity(0.15)),
            in: .rect(cornerRadius: 16, style: .continuous)
        )
    }

    private var connectButton: some View {
        let enabled = canConnect && !isLoading
        return Button(action: attemptLogin) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Conectar")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(GlassButtonStyle(enabled: enabled))
        .disabled(!enabled)
    }

    private func attemptLogin() {
        guard canConnect, !isLoading else { return }
        focusedField = nil
        // Set synchronously before creating the Task so the button
        // is disabled before any re-render can allow a second tap
        isLoading = true
        errorMessage = nil
        Task { await doLogin() }
    }

    private func doLogin() async {
        defer { isLoading = false }
        do {
            try await session.login(
                serverURL: serverURL.trimmed,
                username: username.trimmed,
                password: password.trimmed
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Glass Field

private struct LoginGlassField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure = false
    let field: LoginField
    var focusedField: FocusState<LoginField?>.Binding
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(keyboardType)
        .submitLabel(submitLabel)
        .onSubmit(onSubmit)
        .focused(focusedField, equals: field)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .glassEffect(
            .regular.tint(.white.opacity(0.06)),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
    }
}

// MARK: - Glass Button Style

private struct GlassButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .glassEffect(
                .regular.tint(.blue.opacity(configuration.isPressed ? 0.5 : 0.35)),
                in: .rect(cornerRadius: 20, style: .continuous)
            )
    }
}

// MARK: - Background

private struct LoginAmbientBackground: View {
    var body: some View {
        ZStack {
            DarkBackground()

            Circle()
                .fill(Color.blue.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 95)
                .offset(x: -120, y: -280)

            Circle()
                .fill(Color.indigo.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 140, y: -60)

            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 85)
                .offset(x: -80, y: 360)
        }
    }
}

// MARK: - Helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
