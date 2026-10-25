import SwiftUI

struct EQView: View {
    @EnvironmentObject var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Toggle("Equalizer", isOn: $player.eqEnabled)
                    .font(.headline)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<8, id: \.self) { i in
                        VStack(spacing: 10) {
                            Text(String(format: "%+.0f", Double(player.gains[i])))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(get: { Double(player.gains[i]) },
                                                  set: { player.setGain(i, Float($0)) }),
                                   in: -12...12, step: 1)
                                .frame(width: 180)
                                .rotationEffect(.degrees(-90))
                                .frame(width: 32, height: 180)
                            Text(PlayerModel.frequencyLabels[i])
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .opacity(player.eqEnabled ? 1 : 0.4)
                .disabled(!player.eqEnabled)

                Text("dB gain per frequency band (Hz)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(PlayerModel.presets) { p in
                            Button(p.name) { player.setGains(p.gains) }
                        }
                    } label: { Label("Presets", systemImage: "wand.and.stars") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
