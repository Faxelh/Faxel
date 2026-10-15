import SwiftUI

/// Mini-lecteur posé au-dessus de la barre d'onglets.
struct MiniPlayer: View {
    @EnvironmentObject var player: AudioPlayer
    @ObservedObject private var library = MediaLibrary.shared
    let open: () -> Void

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TrackArtwork(track: track, width: 42, height: 42, radius: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.title(track))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(library.artist(track))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                ClockProgressLine(clock: player.clock)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
        }
    }

}

/// Lecteur plein écran : fond animé tiré de la pochette, pochette qui bat au rythme
/// des basses (plusieurs styles), visualiseur, commandes, volume, « À suivre ».
struct NowPlayingView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = MediaLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("faxelCoverStyle") private var coverStyle = "square"
    @AppStorage("faxelVisualizer") private var visualizer = "bars"
    @AppStorage("faxelBackground") private var backgroundStyle = "artwork"
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var picking: Track?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let cover = min(width - 64, geometry.size.height * 0.36)
            VStack(spacing: 0) {
                if let track = player.current {
                    topBar(track)
                    Spacer(minLength: 8)
                    if showLyrics {
                        LiveLyricsView(clock: player.clock, track: track) { player.seek(to: $0) }
                            .frame(height: cover + 50)
                            .transition(.opacity)
                    } else {
                        PlayerCoverView(meter: player.meter, track: track, style: coverStyle,
                                        playing: player.isPlaying, size: cover)
                            .frame(height: cover + 10)
                            .id(track.path)
                            .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                    removal: .opacity))
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 30)
                                    .onEnded { value in
                                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                            if value.translation.width < -60 { player.next() }
                                            if value.translation.width > 60 { player.previous() }
                                        }
                                    }
                            )
                        PlayerVisualizerView(meter: player.meter, style: visualizer, playing: player.isPlaying)
                            .frame(width: cover, height: visualizer == "none" ? 0 : 38)
                            .padding(.top, 12)
                    }
                    Spacer(minLength: 10)
                    titleRow(track)
                    PlayerScrubber(clock: player.clock) { player.seek(to: $0) }
                        .padding(.top, 14)
                    transport
                        .padding(.top, 6)
                    VolumeRow()
                        .padding(.top, 10)
                    toolsRow(track)
                        .padding(.top, 8)
                    nextUp
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                } else {
                    Spacer()
                    EmptyState(icon: "music.note", title: L("Aucune lecture en cours"))
                    Button(L("Fermer")) { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 80)
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .frame(width: width, height: geometry.size.height)
            .foregroundColor(.white)
        }
        .background {
            PlayerBackground(track: player.current, meter: player.meter, style: backgroundStyle)
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear { player.spectrumWanted = true }
        .onDisappear { player.spectrumWanted = false }
        .sheet(isPresented: $showQueue) {
            QueueSheet()
                .environmentObject(player)
                .environmentObject(model)
        }
        .sheet(item: $picking) { track in
            PlaylistPicker(track: track)
                .environmentObject(model)
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView()
                .environmentObject(player)
        }
        .coverEditor()
    }

    // MARK: Parties

    private func topBar(_ track: Track) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            Spacer()
            VStack(spacing: 1) {
                Text(L("En cours de lecture").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.7)
                Text(L("{index} sur {count}", ["index": "\(player.index + 1)", "count": "\(player.queue.count)"]))
                    .font(.system(size: 13, weight: .bold))
            }
            Spacer()
            Menu {
                TrackMenuItems(track: track, picking: $picking)
                CoverMenuItems(track: track)
                Section(L("Pochette")) {
                    Picker(L("Pochette"), selection: $coverStyle) {
                        Label(L("Pochette"), systemImage: "square.fill").tag("square")
                        Label(L("Vinyle qui tourne"), systemImage: "record.circle").tag("vinyl")
                        Label(L("Rond qui pulse"), systemImage: "circle.fill").tag("round")
                        Label(L("Néon"), systemImage: "light.max").tag("neon")
                        Label(L("CD irisé"), systemImage: "opticaldisc").tag("cd")
                        Label(L("Cassette"), systemImage: "recordingtape").tag("cassette")
                        Label(L("Polaroid"), systemImage: "photo").tag("polaroid")
                        Label(L("Reflet flottant"), systemImage: "square.on.square").tag("floating")
                    }
                }
                Section(L("Fond")) {
                    Picker(L("Fond"), selection: $backgroundStyle) {
                        Label(L("Pochette floue"), systemImage: "photo.fill").tag("artwork")
                        Label(L("Aurore animée"), systemImage: "sparkles").tag("aurora")
                        Label(L("Dégradé arc-en-ciel"), systemImage: "rainbow").tag("rainbow")
                        Label(L("Noir profond"), systemImage: "moon.fill").tag("black")
                    }
                }
                Section(L("Visualiseur")) {
                    Picker(L("Visualiseur"), selection: $visualizer) {
                        Label(L("Barres"), systemImage: "chart.bar.fill").tag("bars")
                        Label(L("Barres miroir"), systemImage: "waveform").tag("mirror")
                        Label(L("Onde"), systemImage: "waveform.path").tag("wave")
                        Label(L("Arc-en-ciel"), systemImage: "rainbow").tag("rainbow")
                        Label(L("Points"), systemImage: "circle.grid.3x3.fill").tag("dots")
                        Label(L("Aucun"), systemImage: "nosign").tag("none")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.top, 8)
    }

    private func titleRow(_ track: Track) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.title(track))
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text([library.artist(track), library.album(track) ?? ""].filter { !$0.isEmpty }
                        .joined(separator: " — "))
                    .font(.system(size: 16))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { model.toggleFavorite(track) }
            } label: {
                Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(model.isFavorite(track) ? .brand : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
    }

    private var transport: some View {
        HStack {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.shuffle ? .brand : Color.white.opacity(0.75))
            }
            Spacer()
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
            }
            Spacer()
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 78, height: 78)
                    .background(Circle().fill(Color.white))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .scaleEffect(player.isPlaying ? 1 : 0.94)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: player.isPlaying)
            }
            Spacer()
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
            }
            Spacer()
            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.repeatMode == .off ? Color.white.opacity(0.75) : .brand)
            }
        }
        .padding(.horizontal, 4)
    }

    private func toolsRow(_ track: Track) -> some View {
        HStack {
            Menu {
                ForEach([0, 15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes)
                    } label: {
                        Text(minutes == 0 ? L("Désactivé") : L("{minutes} min", ["minutes": "\(minutes)"]))
                    }
                }
            } label: {
                toolIcon(player.sleepEnd == nil ? "moon.zzz" : "moon.zzz.fill", active: player.sleepEnd != nil)
            }
            Spacer()
            Menu {
                ForEach(speeds, id: \.self) { value in
                    Button {
                        player.setRate(value)
                    } label: {
                        if value == player.rate {
                            Label(speedText(value), systemImage: "checkmark")
                        } else {
                            Text(speedText(value))
                        }
                    }
                }
            } label: {
                Text(speedText(player.rate))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(player.rate == 1 ? Color.white.opacity(0.8) : .brand)
                    .frame(width: 44, height: 40)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
            } label: {
                toolIcon(showLyrics ? "quote.bubble.fill" : "quote.bubble", active: showLyrics)
            }
            Spacer()
            Button {
                showEqualizer = true
            } label: {
                toolIcon("slider.horizontal.3", active: player.eqEnabled)
            }
            Spacer()
            AirPlayButton(tint: .white)
                .frame(width: 40, height: 40)
            Spacer()
            Button {
                showQueue = true
            } label: {
                toolIcon("list.bullet", active: false)
            }
        }
    }

    private func toolIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(active ? .brand : Color.white.opacity(0.8))
            .frame(width: 40, height: 40)
    }

    /// Petite carte « À suivre » : le morceau suivant, touchez pour y aller.
    @ViewBuilder
    private var nextUp: some View {
        if player.queue.indices.contains(player.index + 1) {
            let next = player.queue[player.index + 1]
            Button {
                player.jump(to: player.index + 1)
            } label: {
                HStack(spacing: 10) {
                    TrackArtwork(track: next, width: 38, height: 38, radius: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("À suivre").uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .opacity(0.6)
                        Text(library.title(next))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                        .opacity(0.7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var speeds: [Float] { [0.5, 0.75, 1, 1.25, 1.5, 2] }

    private func speedText(_ value: Float) -> String {
        let text = value == Float(Int(value)) ? "\(Int(value))" : String(format: "%g", value)
        return text.replacingOccurrences(of: ".", with: Lang.code == "fr" ? "," : ".") + "×"
    }
}

/// File de lecture (« À suivre ») : toucher pour sauter, glisser pour réordonner ou retirer.
struct QueueSheet: View {
    @EnvironmentObject var player: AudioPlayer
    @ObservedObject private var library = MediaLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { offset, track in
                    HStack(spacing: 12) {
                        TrackArtwork(track: track, width: 44, height: 44, radius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.title(track))
                                .font(.system(size: 15, weight: offset == player.index ? .bold : .regular))
                                .foregroundColor(offset == player.index ? .brand : .primary)
                                .lineLimit(1)
                            Text(library.artist(track))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if offset == player.index {
                            PlayingBars(playing: player.isPlaying)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.jump(to: offset)
                    }
                    .deleteDisabled(offset == player.index)
                }
                .onDelete { offsets in
                    player.removeFromQueue(at: offsets)
                }
                .onMove { source, destination in
                    player.moveInQueue(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("À suivre"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Actions du lecteur plein écran (favori, playlist, partage).
struct TrackMenuItems: View {
    @EnvironmentObject var model: AppModel
    let track: Track
    @Binding var picking: Track?

    var body: some View {
        Button {
            model.toggleFavorite(track)
        } label: {
            if model.isFavorite(track) {
                Label(L("Retirer des favoris"), systemImage: "heart.slash")
            } else {
                Label(L("Favori"), systemImage: "heart")
            }
        }
        Button {
            picking = track
        } label: {
            Label(L("Ajouter à une playlist"), systemImage: "text.badge.plus")
        }
        if track.exists {
            ShareLink(item: track.fileURL) {
                Label(L("Partager"), systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// Fine barre de progression du mini-lecteur.
struct ClockProgressLine: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.brand)
                .frame(width: geometry.size.width * progress, height: 2)
        }
        .frame(height: 2)
    }

    private var progress: CGFloat {
        guard clock.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, clock.currentTime / clock.duration)))
    }
}

/// Curseur de position du lecteur plein écran.
struct PlayerScrubber: View {
    @ObservedObject var clock: PlaybackClock
    let seek: (Double) -> Void
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { scrubbing ? scrubValue : clock.currentTime },
                set: { scrubValue = $0 }
            ), in: 0...max(clock.duration, 1), onEditingChanged: { editing in
                if editing {
                    scrubValue = clock.currentTime
                    scrubbing = true
                } else {
                    seek(scrubValue)
                    scrubbing = false
                }
            })
            .tint(.white)
            HStack {
                Text(Fmt.clock(scrubbing ? scrubValue : clock.currentTime))
                Spacer()
                Text("-" + Fmt.clock(max(0, clock.duration - (scrubbing ? scrubValue : clock.currentTime))))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundColor(.white.opacity(0.7))
        }
    }
}
