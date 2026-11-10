import SwiftUI

struct ContentView: View {
    @State private var showPlayer = false

    var body: some View {
        TabView {
            LibraryView(showPlayer: $showPlayer)
                .tabItem { Label("Library", systemImage: "music.note.list") }
            PlaylistsView(showPlayer: $showPlayer)
                .tabItem { Label("Playlists", systemImage: "rectangle.stack") }
            SettingsView(showPlayer: $showPlayer)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showPlayer) { PlayerView() }
    }
}
