import MediaPlayer
import SwiftUI

// MARK: - Fond du lecteur

/// Fond du lecteur plein écran : pochette floue, lueurs de couleur qui dérivent
/// lentement, et une lueur qui respire avec les basses.
struct PlayerBackground: View {
    @ObservedObject private var library = MediaLibrary.shared
    let track: Track?
    let meter: SpectrumMeter
    var style = "artwork"

    var body: some View {
        let colors = artworkColors(track?.id ?? "faxel")
        ZStack {
            switch style {
            case "black":
                Color.black
            case "rainbow":
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate * 12
                    AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                    center: .center, angle: .degrees(angle))
                        .scaleEffect(2)
                        .blur(radius: 50)
                        .opacity(0.8)
                }
            default:
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if style == "artwork", let track = track, let link = library.artwork(track), let url = URL(string: link) {
                Color.clear
                    .overlay(
                        LocalImage(url: url)
                            .scaleEffect(1.4)
                            .blur(radius: 60)
                    )
                    .clipped()
                    .opacity(0.9)
            }
            if style != "black" {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    let blobs: [(Color, Double, Double, Double)] = [
                        (colors.first ?? .purple, 0.07, 0.25, 0.2),
                        (colors.last ?? .blue, 0.05, 0.75, 0.55),
                        (.white, 0.04, 0.5, 0.85),
                    ]
                    for (index, blob) in blobs.enumerated() {
                        let phase = time * blob.1 + Double(index) * 2.1
                        let center = CGPoint(x: size.width * (blob.2 + 0.18 * sin(phase)),
                                             y: size.height * (blob.3 + 0.08 * cos(phase * 1.3)))
                        let radius = size.width * 0.75
                        let opacity = index == 2 ? 0.06 : (style == "aurora" ? 0.55 : 0.28)
                        canvas.fill(
                            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2)),
                            with: .radialGradient(Gradient(colors: [blob.0.opacity(opacity), blob.0.opacity(0)]),
                                                  center: center, startRadius: 0, endRadius: radius))
                    }
                }
            }
            }
            BassGlow(meter: meter, color: colors.first ?? .brand)
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Lueur douce au centre, qui grandit avec les basses.
private struct BassGlow: View {
    @ObservedObject var meter: SpectrumMeter
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let bass = CGFloat(meter.bass)
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.18 + bass * 0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: geometry.size.width * 0.6))
                .frame(width: geometry.size.width * 1.2, height: geometry.size.width * 1.2)
                .scaleEffect(1 + bass * 0.25)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.32)
                .animation(.easeOut(duration: 0.12), value: meter.bass)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pochette

/// Pochette du lecteur : carré, rond, vinyle qui tourne ou néon — elle bat avec les basses.
struct PlayerCoverView: View {
    @ObservedObject var meter: SpectrumMeter
    let track: Track
    let style: String
    let playing: Bool
    let size: CGFloat

    private var pulse: CGFloat {
        playing ? 1 + CGFloat(meter.bass) * 0.05 : 0.9
    }

    var body: some View {
        let colors = artworkColors(track.id)
        Group {
            switch style {
            case "vinyl":
                vinyl
            case "cd":
                cd
            case "cassette":
                cassette
            case "polaroid":
                VStack(spacing: 0) {
                    TrackArtwork(track: track, width: size * 0.72, height: size * 0.72, radius: 2)
                    Text(MediaLibrary.shared.title(track))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundColor(.black.opacity(0.75))
                        .lineLimit(1)
                        .frame(width: size * 0.72, height: size * 0.13)
                }
                .padding(size * 0.04)
                .background(Color(white: 0.97))
                .rotationEffect(.degrees(playing ? -3 : 0))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
                .scaleEffect(pulse)
            case "floating":
                VStack(spacing: 4) {
                    TrackArtwork(track: track, width: size * 0.7, height: size * 0.7, radius: 18)
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                    TrackArtwork(track: track, width: size * 0.7, height: size * 0.7, radius: 18)
                        .scaleEffect(x: 1, y: -1)
                        .frame(height: size * 0.22, alignment: .top)
                        .clipped()
                        .mask(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                }
                .offset(y: playing ? -CGFloat(meter.bass) * 10 : 0)
            case "round":
                ZStack {
                    Circle()
                        .stroke(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom), lineWidth: 4)
                        .frame(width: size * 0.92, height: size * 0.92)
                        .scaleEffect(1 + CGFloat(meter.bass) * 0.12)
                        .opacity(0.4 + Double(meter.bass) * 0.6)
                    TrackArtwork(track: track, width: size * 0.82, height: size * 0.82, radius: size)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                        .scaleEffect(pulse)
                }
            case "neon":
                TrackArtwork(track: track, width: size * 0.9, height: size * 0.9, radius: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 3)
                    )
                    .shadow(color: (colors.first ?? .brand).opacity(0.5 + Double(meter.bass) * 0.5),
                            radius: 18 + CGFloat(meter.bass) * 30)
                    .shadow(color: (colors.last ?? .brand).opacity(0.4), radius: 40)
                    .scaleEffect(pulse)
            default:
                TrackArtwork(track: track, width: size * 0.92, height: size * 0.92, radius: 22)
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
                    .scaleEffect(pulse)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: meter.bass)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: playing)
    }

    /// CD irisé qui tourne : reflets arc-en-ciel, pochette au centre.
    private var cd: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 70
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [Color(white: 0.85), .cyan.opacity(0.7), .pink.opacity(0.6),
                                                   .yellow.opacity(0.6), Color(white: 0.9), .purple.opacity(0.6),
                                                   Color(white: 0.85)], center: .center))
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                TrackArtwork(track: track, width: size * 0.42, height: size * 0.42, radius: size)
                    .clipShape(Circle())
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: size * 0.12, height: size * 0.12)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
            }
            .frame(width: size * 0.92, height: size * 0.92)
            .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
            .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
            .scaleEffect(playing ? 1 + CGFloat(meter.bass) * 0.02 : 0.92)
        }
    }

    /// Cassette : étiquette avec la pochette et le titre, bobines qui tournent.
    private var cassette: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 120
            VStack(spacing: size * 0.05) {
                HStack(spacing: 10) {
                    TrackArtwork(track: track, width: size * 0.2, height: size * 0.2, radius: 4)
                    Text(MediaLibrary.shared.title(track))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.black.opacity(0.8))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.93)))
                HStack(spacing: size * 0.22) {
                    reel(angle)
                    reel(angle * 0.8)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.55)))
            }
            .padding(size * 0.05)
            .frame(width: size * 0.95)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .scaleEffect(pulse)
        }
    }

    private func reel(_ angle: Double) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.85))
            ForEach(0..<3, id: \.self) { spoke in
                Capsule()
                    .fill(Color(white: 0.3))
                    .frame(width: size * 0.025, height: size * 0.11)
                    .rotationEffect(.degrees(Double(spoke) * 60))
            }
            Circle().fill(Color(white: 0.3)).frame(width: size * 0.04, height: size * 0.04)
        }
        .frame(width: size * 0.14, height: size * 0.14)
        .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
    }

    /// Disque vinyle : sillons, étiquette avec la pochette, il tourne pendant la lecture.
    private var vinyl: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate * 40
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.18), Color(white: 0.04)],
                                         center: .center, startRadius: 0, endRadius: size / 2))
                ForEach(0..<9, id: \.self) { ring in
                    Circle()
                        .stroke(Color.white.opacity(ring % 2 == 0 ? 0.06 : 0.03), lineWidth: 1)
                        .frame(width: size * (0.48 + CGFloat(ring) * 0.055), height: size * (0.48 + CGFloat(ring) * 0.055))
                }
                // Reflet
                Circle()
                    .trim(from: 0.05, to: 0.18)
                    .stroke(Color.white.opacity(0.18), lineWidth: size * 0.3)
                    .frame(width: size * 0.65, height: size * 0.65)
                TrackArtwork(track: track, width: size * 0.4, height: size * 0.4, radius: size)
                    .clipShape(Circle())
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.035, height: size * 0.035)
            }
            .frame(width: size * 0.95, height: size * 0.95)
            .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .scaleEffect(playing ? 1 + CGFloat(meter.bass) * 0.02 : 0.92)
        }
    }
}

// MARK: - Visualiseur

/// Visualiseur sous la pochette : barres, barres miroir ou onde.
struct PlayerVisualizerView: View {
    @ObservedObject var meter: SpectrumMeter
    let style: String
    let playing: Bool

    var body: some View {
        switch style {
        case "none":
            EmptyView()
        case "mirror":
            mirror
        case "wave":
            wave
        case "rainbow":
            rainbow
        case "dots":
            dots
        default:
            SpectrumBarsView(meter: meter)
                .opacity(playing ? 0.9 : 0.3)
        }
    }

    private var values: [Float] {
        let spectrum = meter.spectrum
        let count = 28
        guard spectrum.count > count else { return spectrum }
        let step = max(1, spectrum.count / count)
        return stride(from: 0, to: spectrum.count, by: step).map { spectrum[$0] }
    }

    private var mirror: some View {
        GeometryReader { geometry in
            let list = values
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(Color.white.opacity(0.35 + Double(value) * 0.65))
                        .frame(height: max(3, CGFloat(value) * geometry.size.height))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .opacity(playing ? 1 : 0.3)
    }

    private var rainbow: some View {
        GeometryReader { geometry in
            let list = values
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hue: Double(index) / Double(max(1, list.count)), saturation: 0.75, brightness: 1))
                        .frame(height: max(3, CGFloat(value) * geometry.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(playing ? 1 : 0.3)
    }

    private var dots: some View {
        GeometryReader { geometry in
            let list = values
            let rows = 5
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { row in
                            let lit = Float(rows - row) / Float(rows) <= value + 0.05
                            Circle()
                                .fill(Color.white.opacity(lit ? 0.95 : 0.12))
                                .frame(width: (geometry.size.height - CGFloat(rows - 1) * 3) / CGFloat(rows),
                                       height: (geometry.size.height - CGFloat(rows - 1) * 3) / CGFloat(rows))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .opacity(playing ? 1 : 0.3)
    }

    private var wave: some View {
        let list = values
        return Canvas { canvas, size in
            guard list.count > 1 else { return }
            for layer in 0..<2 {
                var path = Path()
                let middle = size.height / 2
                let step = size.width / CGFloat(list.count - 1)
                for (index, value) in list.enumerated() {
                    let sign: CGFloat = index % 2 == 0 ? 1 : -1
                    let amplitude = CGFloat(value) * middle * (layer == 0 ? 1 : 0.6) * sign
                    let point = CGPoint(x: CGFloat(index) * step, y: middle - amplitude)
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        let previous = CGPoint(x: CGFloat(index - 1) * step, y: path.currentPoint?.y ?? middle)
                        path.addQuadCurve(to: point, control: CGPoint(x: (previous.x + point.x) / 2, y: previous.y))
                    }
                }
                canvas.stroke(path, with: .color(.white.opacity(layer == 0 ? 0.9 : 0.4)),
                              style: StrokeStyle(lineWidth: layer == 0 ? 2.5 : 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .opacity(playing ? 1 : 0.3)
    }
}

// MARK: - Volume

/// Volume du téléphone, réglable directement dans le lecteur.
struct VolumeRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13))
                .opacity(0.7)
            SystemVolumeSlider()
                .frame(height: 30)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 13))
                .opacity(0.7)
        }
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = .white
        if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Paroles

/// Paroles dans le lecteur : synchronisées (la ligne chantée s'allume et défile toute seule,
/// touchez une ligne pour y aller) ou texte simple ; recherche en ligne si le fichier n'en a pas.
struct LiveLyricsView: View {
    @ObservedObject private var store = LyricsStore.shared
    @ObservedObject var clock: PlaybackClock
    let track: Track
    let seek: (Double) -> Void
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 8) {
            if store.loading || (store.searching && store.lyrics == nil) {
                Spacer()
                ProgressView().tint(.white)
                Text(L("Recherche des paroles…"))
                    .font(.system(size: 15))
                    .opacity(0.7)
                Spacer()
            } else if let lyrics = store.lyrics {
                if lyrics.isSynced {
                    synced(lyrics)
                } else {
                    ScrollView {
                        Text(lyrics.lines.map { $0.text }.joined(separator: "\n"))
                            .font(.system(size: 22, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                }
                HStack {
                    Text(sourceText(lyrics))
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.5)
                    Spacer()
                    Menu {
                        Button {
                            showSearch = true
                        } label: {
                            Label(L("Chercher d'autres paroles"), systemImage: "magnifyingglass")
                        }
                        if lyrics.source == .saved || lyrics.source == .online {
                            Button(role: .destructive) {
                                store.delete(for: track)
                            } label: {
                                Label(L("Supprimer ces paroles"), systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .opacity(0.7)
                    }
                }
            } else {
                Spacer()
                Image(systemName: "quote.bubble")
                    .font(.system(size: 36))
                    .opacity(0.6)
                Text(store.searched ? L("Aucune parole trouvée en ligne.") : L("Aucune parole dans ce fichier."))
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0.8)
                Button {
                    showSearch = true
                } label: {
                    Label(L("Chercher en ligne"), systemImage: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                Spacer()
            }
        }
        .onAppear { store.load(track, autoSearch: true) }
        .onChange(of: track.path) { _ in store.load(track, autoSearch: true) }
        .sheet(isPresented: $showSearch) {
            LyricsSearchSheet(track: track)
        }
    }

    private func sourceText(_ lyrics: Lyrics) -> String {
        switch lyrics.source {
        case .online: return L("Paroles : LRCLIB")
        case .file: return L("Paroles : fichier .lrc")
        case .embedded: return L("Paroles : dans le fichier")
        case .saved: return L("Paroles enregistrées")
        }
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        let current = lyrics.currentIndex(at: clock.currentTime)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 60)
                    ForEach(lyrics.lines) { line in
                        let active = line.id == current
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: active ? 28 : 24, weight: .heavy))
                            .foregroundColor(.white.opacity(active ? 1 : ((current ?? -1) > line.id ? 0.35 : 0.5)))
                            .shadow(color: .white.opacity(active ? 0.5 : 0), radius: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .onTapGesture {
                                if let time = line.time { seek(time) }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: active)
                    }
                    Color.clear.frame(height: 160)
                }
            }
            .mask(LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .onChange(of: current) { index in
                guard let index = index else { return }
                withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(index, anchor: .center) }
            }
            .onAppear {
                if let index = current { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }
}

/// Recherche manuelle des paroles (titre et artiste modifiables).
struct LyricsSearchSheet: View {
    @ObservedObject private var store = LyricsStore.shared
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(L("Titre et artiste"), text: $query)
                            .submitLabel(.search)
                            .onSubmit { store.search(track, query: query) }
                        if store.searching {
                            ProgressView()
                        } else {
                            Button {
                                store.search(track, query: query)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                }
                Section(L("Résultats")) {
                    if store.results.isEmpty && !store.searching {
                        Text(L("Aucun résultat."))
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.results) { result in
                        Button {
                            store.use(result, for: track)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.track)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(result.artist + (result.duration > 0 ? " · " + Fmt.clock(result.duration) : ""))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Text(result.hasSynced ? L("Synchronisées") : L("Texte simple"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(result.hasSynced ? .green : .orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Paroles"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
            }
        }
        .onAppear {
            let guess = LyricsStore.guess(track)
            query = [guess.title, guess.artist ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            if store.results.isEmpty { store.search(track, query: query) }
        }
    }
}
