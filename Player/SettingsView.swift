import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: Library
    @Binding var showPlayer: Bool
    @AppStorage("themeName") private var themeName = AppTheme.red.rawValue
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("sortOrder") private var sortOrder = SortOrder.title.rawValue
    @State private var currentIcon = ""
    @State private var iconError: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Mode", selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Theme Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 14)], spacing: 14) {
                        ForEach(AppTheme.allCases) { t in
                            Button { themeName = t.rawValue } label: {
                                Circle().fill(t.color)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        if themeName == t.rawValue {
                                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(Circle().stroke(Color.primary.opacity(themeName == t.rawValue ? 0.5 : 0), lineWidth: 3).padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.name)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("App Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 14)], spacing: 14) {
                        ForEach(IconOption.all) { opt in
                            Button { setIcon(opt) } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(LinearGradient(colors: opt.colors, startPoint: .top, endPoint: .bottom))
                                        .frame(width: 60, height: 60)
                                        .overlay(Image(systemName: "music.note").font(.system(size: 28, weight: .bold)).foregroundStyle(.white))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                                .stroke(Color.primary.opacity(currentIcon == opt.id ? 0.6 : 0), lineWidth: 3)
                                                .padding(-4)
                                        )
                                    Text(opt.name).font(.caption).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Library") {
                    Picker("Sort Songs By", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    HStack {
                        Text("Songs")
                        Spacer()
                        Text("\(library.songs.count)").foregroundStyle(.secondary)
                    }
                    Button("Delete All Songs", role: .destructive) { confirmDelete = true }
                        .disabled(library.songs.isEmpty)
                }

                Section("About") {
                    HStack {
                        Text("Player")
                        Spacer()
                        Text("Version 1.0").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { currentIcon = UIApplication.shared.alternateIconName ?? "" }
            .alert("Delete all songs?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { library.delete(library.songs.map { $0.id }) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every song from Player. Your original files in Files are not touched.")
            }
            .alert("Couldn't change icon", isPresented: Binding(get: { iconError != nil }, set: { if !$0 { iconError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(iconError ?? "")
            }
        }
        .miniPlayer($showPlayer)
    }

    private func setIcon(_ opt: IconOption) {
        guard UIApplication.shared.supportsAlternateIcons else {
            iconError = "Alternate icons aren't supported here."
            return
        }
        UIApplication.shared.setAlternateIconName(opt.altName) { error in
            DispatchQueue.main.async {
                if let error { iconError = error.localizedDescription } else { currentIcon = opt.id }
            }
        }
    }
}
