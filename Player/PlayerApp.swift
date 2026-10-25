import SwiftUI

@main
struct PlayerApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = PlayerModel()
    @AppStorage("themeName") private var themeName = AppTheme.red.rawValue
    @AppStorage("appearance") private var appearance = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            let color = AppTheme(rawValue: themeName)?.color ?? .red
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environment(\.accent, color)
                .tint(color)
                .preferredColorScheme(appearance == 1 ? .light : (appearance == 2 ? .dark : nil))
                .onAppear {
                    library.onDelete = { id in player.removeSong(id) }
                    library.scanDropFolder()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { library.scanDropFolder() }
                }
        }
    }
}
