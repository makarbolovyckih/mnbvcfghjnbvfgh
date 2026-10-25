import SwiftUI

struct QueueView: View {
    @EnvironmentObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    var body: some View {
        NavigationStack {
            List {
                if let song = player.current {
                    Section("Now Playing") { SongRow(song: song, isCurrent: true) }
                }
                Section {
                    ForEach(player.upNext) { item in
                        Button { player.jump(to: item) } label: { SongRow(song: item.song) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { player.removeUpNext(at: $0) }
                    .onMove { player.moveUpNext(from: $0, to: $1) }
                } header: {
                    HStack {
                        Text("Up Next")
                        Spacer()
                        if player.isShuffled {
                            Label("Shuffle on", systemImage: "shuffle").font(.caption).foregroundStyle(accent)
                        }
                    }
                } footer: {
                    if player.upNext.isEmpty { Text("Nothing queued. Long-press a song to add it.") }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
