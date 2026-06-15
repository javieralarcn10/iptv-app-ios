import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        if session.isLoggedIn {
            HomeView()
        } else {
            LoginView()
        }
    }
}
