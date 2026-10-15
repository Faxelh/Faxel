import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Lecteur vidéo plein écran : portrait / paysage, sous-titres, vitesse,
/// pistes audio, gestes (double-toucher pour avancer, glisser pour la
/// luminosité et le volume, pincer pour remplir l'écran), verrou.
struct VideoPlayerView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var video: VideoPlayerModel
    @ObservedObject private var library = MediaLibrary.shared
    let session: VideoSession

    @AppStorage("subtitleSize") private var subtitleSize = 2
    @AppStorage("subtitleBackground") private var subtitleBackground = true
    @AppStorage("autoLandscape") private var autoLandscape = true

    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var touchLocked = false
    @State private var rotationLocked = false
    @State private var seekFlash: (forward: Bool, amount: Int)?
    @State private var seekFlashWork: DispatchWorkItem?
    @State private var hud: (icon: String, value: Double, left: Bool)?
    @State private var scrubStart: Double = 0
    @State private var scrubPreview: Double?
    @State private var watermarkTrack: Track?
    @State private var snapshotImage: UIImage?
    @State private var dragStart: CGFloat = 0
    @State private var dragKind = 0
    @State private var pinchHandled = false
    @State private var importingSubtitle = false
    @State private var noticeText: String?

    private static let speeds: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(video: video, fill: video.fill)
                    .ignoresSafeArea()
                HiddenVolumeView()
                    .frame(width: 2, height: 2)
                    .allowsHitTesting(false)

                gestureLayer(size: geometry.size)

                subtitleLayer(landscape: landscape)

                if video.isBuffering && !scrubbing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                        .allowsHitTesting(false)
                }

                if let flash = seekFlash {
                    seekBubble(flash.forward, flash.amount)
                        .frame(maxWidth: .infinity, alignment: flash.forward ? .trailing : .leading)
                        .padding(.horizontal, landscape ? 90 : 40)
                        .allowsHitTesting(false)
                }

                if let hud = hud {
                    hudView(hud.icon, hud.value)
                        .frame(maxWidth: .infinity, alignment: hud.left ? .leading : .trailing)
                        .padding(.horizontal, landscape ? 70 : 28)
                        .allowsHitTesting(false)
                }

                if let target = scrubPreview {
                    scrubBubble(target)
                        .allowsHitTesting(false)
                }

                if video.boosted {
                    VStack {
                        Label(L("Vitesse ×2"), systemImage: "forward.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .padding(.top, landscape ? 24 : 70)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if showNextCard {
                    nextEpisodeCard(landscape: landscape)
                }

                if touchLocked {
                    lockedOverlay
                } else if controlsVisible {
                    controls(landscape: landscape)
                        .transition(.opacity)
                }

                if let text = noticeText {
                    VStack {
                        Text(text)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                            .padding(.top, landscape ? 60 : 110)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!controlsVisible || touchLocked)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
        .onDisappear(perform: finish)
        .onChange(of: video.notice) { text in
            guard let text = text else { return }
            showNotice(text)
            video.notice = nil
        }
        .onChange(of: video.isPlaying) { playing in
            if playing { scheduleHide() } else { showControls(autoHide: false) }
        }
        .onChange(of: video.index) { _ in
            autoRotate()
        }
        .onChange(of: library.metas[video.current?.path ?? ""]) { _ in
            autoRotate()
        }
        .sheet(item: $watermarkTrack) { track in
            WatermarkView(track: track)
                .environmentObject(model)
        }
        .fileImporter(isPresented: $importingSubtitle, allowedContentTypes: subtitleTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                video.importSubtitle(url)
            }
        }
    }

    private var subtitleTypes: [UTType] {
        var types: [UTType] = []
        if let srt = UTType(filenameExtension: "srt") { types.append(srt) }
        if let vtt = UTType(filenameExtension: "vtt") { types.append(vtt) }
        if let ass = UTType(filenameExtension: "ass") { types.append(ass) }
        if let ssa = UTType(filenameExtension: "ssa") { types.append(ssa) }
        types.append(.plainText)
        types.append(.data)
        return types
    }

    // MARK: - Ouverture / fermeture

    private func start() {
        Orientation.allow(.allButUpsideDown)
        // Retour depuis l'Image dans l'image : même file déjà en cours, on ne relance pas.
        let sameContent = video.current != nil && video.items.map { $0.id } == session.items.map { $0.id }
        if !sameContent {
            video.open(session.items, start: session.start)
        }
        autoRotate()
        scheduleHide()
    }

    private func finish() {
        // L'Image dans l'image vient de démarrer : l'écran se referme pour laisser
        // voir le reste de l'app, mais la lecture continue dans la mini-fenêtre.
        if !video.pipActive {
            video.close()
        }
        rotationLocked = false
        Orientation.allow(.portrait)
        Orientation.rotate(to: .portrait)
    }

    private func close() {
        video.close()
        model.videoSession = nil
    }

    /// Vidéo horizontale : passe en paysage (réglable).
    private func autoRotate() {
        guard autoLandscape, !rotationLocked, let track = video.current,
              let meta = library.meta(track), meta.width != nil else { return }
        if meta.isLandscape && !Orientation.isLandscape {
            Orientation.rotate(to: .landscapeRight)
        } else if !meta.isLandscape && Orientation.isLandscape {
            Orientation.rotate(to: .portrait)
        }
    }

    private func toggleRotation() {
        rotationLocked = false
        if Orientation.isLandscape {
            Orientation.allow(.allButUpsideDown)
            Orientation.rotate(to: .portrait)
        } else {
            Orientation.allow(.allButUpsideDown)
            Orientation.rotate(to: .landscapeRight)
        }
        scheduleHide()
    }

    private func toggleRotationLock() {
        rotationLocked.toggle()
        if rotationLocked {
            Orientation.lockCurrent()
            showNotice(L("Rotation verrouillée"))
        } else {
            Orientation.allow(.allButUpsideDown)
            showNotice(L("Rotation automatique"))
        }
        scheduleHide()
    }

    // MARK: - Affichage des commandes

    private func showControls(autoHide: Bool = true) {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
        if autoHide { scheduleHide() } else { hideWork?.cancel() }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem {
            if video.isPlaying && !scrubbing {
                withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func showNotice(_ text: String) {
        withAnimation { noticeText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if noticeText == text {
                withAnimation { noticeText = nil }
            }
        }
    }

    // MARK: - Gestes

    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { location in
                guard !touchLocked else { return }
                let forward = location.x > size.width / 2
                video.skip(by: forward ? 10 : -10)
                flashSeek(forward)
            }
            .onTapGesture { _ in
                if touchLocked {
                    showControls()
                    return
                }
                if controlsVisible {
                    withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
                } else {
                    showControls()
                }
            }
            // Appui long : vitesse ×2 tant que le doigt reste posé (comme YouTube).
            .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 12, perform: {
                guard !touchLocked, video.isPlaying else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                video.setBoost(true)
            }, onPressingChanged: { pressing in
                if !pressing { video.setBoost(false) }
            })
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard !touchLocked else { return }
                        if dragKind == 0 {
                            let vertical = abs(value.translation.height) > abs(value.translation.width)
                            guard vertical else {
                                // Glisser à l'horizontale : avancer ou reculer dans la vidéo.
                                dragKind = 3
                                scrubStart = video.currentTime
                                showControls(autoHide: false)
                                return
                            }
                            if value.startLocation.x < size.width / 2 {
                                dragKind = 1
                                dragStart = DeviceControls.brightness
                            } else {
                                dragKind = 2
                                dragStart = CGFloat(DeviceControls.volume)
                            }
                        }
                        if dragKind == 3 {
                            let span = min(max(video.duration, 1), 180)
                            let offset = Double(value.translation.width / max(size.width, 1)) * span
                            scrubPreview = min(max(0, scrubStart + offset), max(video.duration, 0))
                            return
                        }
                        let delta = -value.translation.height / max(220, size.height * 0.6)
                        let level = min(1, max(0, dragStart + delta))
                        if dragKind == 1 {
                            DeviceControls.brightness = level
                            hud = ("sun.max.fill", Double(level), true)
                        } else if dragKind == 2 {
                            DeviceControls.volume = Float(level)
                            hud = (level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", Double(level), false)
                        }
                    }
                    .onEnded { _ in
                        if dragKind == 2 { DeviceControls.endVolumeGesture() }
                        if dragKind == 3, let target = scrubPreview {
                            video.seek(to: target)
                            scheduleHide()
                        }
                        scrubPreview = nil
                        dragKind = 0
                        withAnimation(.easeOut(duration: 0.4).delay(0.4)) { hud = nil }
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        guard !touchLocked, !pinchHandled else { return }
                        if scale > 1.15 && !video.fill {
                            pinchHandled = true
                            withAnimation { video.fill = true }
                            showNotice(L("Plein écran"))
                        } else if scale < 0.87 && video.fill {
                            pinchHandled = true
                            withAnimation { video.fill = false }
                            showNotice(L("Image entière"))
                        }
                    }
                    .onEnded { _ in pinchHandled = false }
            )
    }

    private func flashSeek(_ forward: Bool) {
        let amount = (seekFlash?.forward == forward ? (seekFlash?.amount ?? 0) : 0) + 10
        withAnimation(.easeOut(duration: 0.15)) { seekFlash = (forward, amount) }
        seekFlashWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) { seekFlash = nil }
        }
        seekFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func seekBubble(_ forward: Bool, _ amount: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: forward ? "goforward" : "gobackward")
                .font(.system(size: 30, weight: .semibold))
            Text(forward ? "+\(amount) s" : "−\(amount) s")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(.white)
        .frame(width: 110, height: 110)
        .background(Circle().fill(Color.white.opacity(0.18)))
    }

    /// Barre verticale : luminosité à gauche, volume à droite.
    private func hudView(_ icon: String, _ value: Double) -> some View {
        VStack(spacing: 10) {
            Text("\(Int(value * 100))")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.white)
                    .frame(height: max(6, 150 * CGFloat(value)))
            }
            .frame(width: 8, height: 150)
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.vertical, 14)
        .frame(width: 52)
        .background(Capsule().fill(Color.black.opacity(0.6)))
    }

    private func scrubBubble(_ target: Double) -> some View {
        let delta = target - scrubStart
        return VStack(spacing: 4) {
            Text(Fmt.clock(target))
                .font(.system(size: 30, weight: .bold).monospacedDigit())
            Text((delta >= 0 ? "+" : "−") + Fmt.clock(abs(delta)))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.75))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.65)))
    }

    // MARK: - Épisode suivant

    private var showNextCard: Bool {
        !touchLocked && video.nextCountdown != nil
    }

    private func nextEpisodeCard(landscape: Bool) -> some View {
        let remaining = video.nextCountdown ?? 0
        let next = video.items.indices.contains(video.index + 1) ? video.items[video.index + 1] : nil
        return VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Épisode suivant dans {n} s", ["n": "\(remaining)"]))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: remaining)
                    if let next = next {
                        Text(next.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Button {
                            video.next()
                        } label: {
                            Label(L("Lire"), systemImage: "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white))
                        }
                        Button {
                            video.cancelAutoNext = true
                        } label: {
                            Text(L("Annuler"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 300, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.75)))
            }
            .padding(.horizontal, landscape ? 60 : 16)
            .padding(.bottom, landscape ? 90 : 140)
        }
        .transition(.opacity)
    }

    // MARK: - Sous-titres

    private var subtitleFont: CGFloat {
        switch subtitleSize {
        case 1: return 15
        case 3: return 24
        case 4: return 30
        default: return 19
        }
    }

    private func subtitleLayer(landscape: Bool) -> some View {
        VStack {
            Spacer()
            if let text = video.subtitleText {
                Text(text)
                    .font(.system(size: landscape ? subtitleFont + 3 : subtitleFont, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(subtitleBackground ? 0.55 : 0))
                    )
                    .padding(.horizontal, landscape ? 60 : 16)
            }
        }
        .padding(.bottom, controlsVisible && !touchLocked ? (landscape ? 96 : 150) : (landscape ? 26 : 60))
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        .allowsHitTesting(false)
    }

    // MARK: - Commandes

    private var lockedOverlay: some View {
        VStack {
            Spacer()
            if controlsVisible {
                Button {
                    touchLocked = false
                    showControls()
                } label: {
                    Label(L("Déverrouiller l'écran"), systemImage: "lock.open.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                .padding(.bottom, 50)
            }
        }
    }

    private func controls(landscape: Bool) -> some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerButtons(landscape: landscape)
                Spacer()
                bottomBar
            }
            .padding(.horizontal, landscape ? 24 : 12)
            .padding(.vertical, landscape ? 8 : 4)
        }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(video.current.map { library.title($0) } ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if video.items.count > 1 {
                    Text(L("{index} sur {count}", ["index": "\(video.index + 1)", "count": "\(video.items.count)"]))
                        .font(.system(size: 12))
                        .opacity(0.7)
                }
            }
            Spacer(minLength: 4)
            AirPlayButton(tint: .white, video: true)
                .frame(width: 40, height: 40)
            if video.pipPossible {
                Button {
                    video.togglePictureInPicture()
                } label: {
                    Image(systemName: video.pipActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
            }
            subtitleMenu
            moreMenu
        }
        .foregroundColor(.white)
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                video.subtitlesOff()
            } label: {
                if video.hasSubtitles {
                    Text(L("Désactivés"))
                } else {
                    Label(L("Désactivés"), systemImage: "checkmark")
                }
            }
            if !video.externalSubtitles.isEmpty {
                Section(L("Fichiers")) {
                    ForEach(video.externalSubtitles, id: \.self) { url in
                        Button {
                            video.selectExternal(url)
                        } label: {
                            if video.selectedExternal == url {
                                Label(SubtitleParser.displayName(url), systemImage: "checkmark")
                            } else {
                                Text(SubtitleParser.displayName(url))
                            }
                        }
                    }
                }
            }
            if !video.embeddedSubtitles.isEmpty {
                Section(L("Intégrés à la vidéo")) {
                    ForEach(video.embeddedSubtitles, id: \.self) { option in
                        Button {
                            video.selectEmbedded(option)
                        } label: {
                            if video.selectedEmbedded == option {
                                Label(VideoPlayerModel.optionName(option), systemImage: "checkmark")
                            } else {
                                Text(VideoPlayerModel.optionName(option))
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    importingSubtitle = true
                } label: {
                    Label(L("Charger un fichier de sous-titres…"), systemImage: "doc.badge.plus")
                }
                Menu {
                    ForEach([1, 2, 3, 4], id: \.self) { size in
                        Button {
                            subtitleSize = size
                        } label: {
                            if subtitleSize == size {
                                Label(sizeName(size), systemImage: "checkmark")
                            } else {
                                Text(sizeName(size))
                            }
                        }
                    }
                    Toggle(L("Fond sombre"), isOn: $subtitleBackground)
                } label: {
                    Label(L("Taille du texte"), systemImage: "textformat.size")
                }
                if video.selectedExternal != nil {
                    Menu {
                        ForEach([-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0], id: \.self) { step in
                            Button {
                                if step == 0 {
                                    video.subtitleDelay = 0
                                } else {
                                    video.subtitleDelay += step
                                }
                                showNotice(L("Décalage : {value} s", ["value": delayText(video.subtitleDelay)]))
                            } label: {
                                Text(stepLabel(step))
                            }
                        }
                    } label: {
                        Label(L("Décalage : {value} s", ["value": delayText(video.subtitleDelay)]), systemImage: "timer")
                    }
                }
            }
        } label: {
            Image(systemName: video.hasSubtitles ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
        }
    }

    private var moreMenu: some View {
        Menu {
            Menu {
                ForEach(VideoPlayerView.speeds, id: \.self) { value in
                    Button {
                        video.setRate(value)
                    } label: {
                        if video.rate == value {
                            Label(speedText(value), systemImage: "checkmark")
                        } else {
                            Text(speedText(value))
                        }
                    }
                }
            } label: {
                Label(L("Vitesse : {value}", ["value": speedText(video.rate)]), systemImage: "speedometer")
            }
            if !video.audioOptions.isEmpty {
                Menu {
                    ForEach(video.audioOptions, id: \.self) { option in
                        Button {
                            video.selectAudio(option)
                        } label: {
                            if video.selectedAudio == option {
                                Label(VideoPlayerModel.optionName(option), systemImage: "checkmark")
                            } else {
                                Text(VideoPlayerModel.optionName(option))
                            }
                        }
                    }
                } label: {
                    Label(L("Piste audio"), systemImage: "waveform")
                }
            }
            Button {
                video.repeatOne.toggle()
                showNotice(video.repeatOne ? L("Répétition de la vidéo activée") : L("Répétition désactivée"))
            } label: {
                Label(L("Répéter cette vidéo"), systemImage: video.repeatOne ? "checkmark" : "repeat.1")
            }
            Menu {
                Button(L("Désactivée")) { video.setSleep(minutes: 0) }
                Button(L("Fin de la vidéo")) {
                    video.setSleep(minutes: -1)
                    showNotice(L("Arrêt à la fin de la vidéo"))
                }
                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button(L("{n} min", ["n": "\(minutes)"])) {
                        video.setSleep(minutes: minutes)
                        showNotice(L("Arrêt dans {n} min", ["n": "\(minutes)"]))
                    }
                }
            } label: {
                Label(sleepLabel, systemImage: "moon.zzz")
            }
            Button {
                video.snapshot { image in
                    guard let image = image else { return }
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    showNotice(L("Capture enregistrée dans Photos"))
                }
            } label: {
                Label(L("Capture d'écran"), systemImage: "camera")
            }
            if let track = video.current {
                Button {
                    video.pause()
                    watermarkTrack = track
                } label: {
                    Label(L("Retirer un filigrane…"), systemImage: "wand.and.stars")
                }
            }
            Button {
                withAnimation { video.fill.toggle() }
            } label: {
                Label(video.fill ? L("Image entière") : L("Remplir l'écran"),
                      systemImage: video.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            Button {
                toggleRotationLock()
            } label: {
                Label(rotationLocked ? L("Déverrouiller la rotation") : L("Verrouiller la rotation"),
                      systemImage: rotationLocked ? "lock.rotation.open" : "lock.rotation")
            }
            Button {
                touchLocked = true
                controlsVisible = false
                showNotice(L("Écran verrouillé : touchez pour déverrouiller"))
            } label: {
                Label(L("Verrouiller l'écran"), systemImage: "lock.fill")
            }
            if let track = video.current {
                ShareLink(item: track.fileURL) {
                    Label(L("Partager"), systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 40, height: 40)
        }
    }

    private func centerButtons(landscape: Bool) -> some View {
        HStack(spacing: landscape ? 54 : 30) {
            if video.items.count > 1 {
                Button {
                    video.previous()
                    scheduleHide()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24))
                }
                .opacity(video.hasPrevious || video.currentTime > 5 ? 1 : 0.4)
            }
            Button {
                video.skip(by: -10)
                flashSeek(false)
                scheduleHide()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 30, weight: .medium))
            }
            Button {
                video.toggle()
            } label: {
                Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.white.opacity(0.16)))
            }
            Button {
                video.skip(by: 10)
                flashSeek(true)
                scheduleHide()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 30, weight: .medium))
            }
            if video.items.count > 1 {
                Button {
                    video.next()
                    scheduleHide()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 24))
                }
                .disabled(!video.hasNext)
                .opacity(video.hasNext ? 1 : 0.4)
            }
        }
        .foregroundColor(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(Fmt.clock(scrubbing ? scrubValue : video.currentTime))
                    .frame(minWidth: 44, alignment: .leading)
                Slider(value: Binding(
                    get: { scrubbing ? scrubValue : min(video.currentTime, max(video.duration, 1)) },
                    set: { value in
                        scrubValue = value
                        if scrubbing { video.seek(to: value) }
                    }
                ), in: 0...max(video.duration, 1), onEditingChanged: { editing in
                    if editing {
                        scrubValue = video.currentTime
                        scrubbing = true
                        hideWork?.cancel()
                    } else {
                        video.seek(to: scrubValue)
                        scrubbing = false
                        scheduleHide()
                    }
                })
                .tint(.brand)
                Text("-" + Fmt.clock(max(0, video.duration - (scrubbing ? scrubValue : video.currentTime))))
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            HStack(spacing: 0) {
                barButton(Orientation.isLandscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate",
                          L("Pivoter")) { toggleRotation() }
                Spacer()
                barButton(rotationLocked ? "lock.rotation" : "lock.rotation.open",
                          rotationLocked ? L("Verrouillée") : L("Auto"), active: rotationLocked) { toggleRotationLock() }
                Spacer()
                barButton(video.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          video.fill ? L("Remplir") : L("Ajuster")) {
                    withAnimation { video.fill.toggle() }
                    scheduleHide()
                }
                Spacer()
                Menu {
                    ForEach(VideoPlayerView.speeds, id: \.self) { value in
                        Button {
                            video.setRate(value)
                        } label: {
                            if video.rate == value {
                                Label(speedText(value), systemImage: "checkmark")
                            } else {
                                Text(speedText(value))
                            }
                        }
                    }
                } label: {
                    barLabel("speedometer", speedText(video.rate), active: video.rate != 1)
                }
                Spacer()
                barButton("lock", L("Écran")) {
                    touchLocked = true
                    controlsVisible = false
                    showNotice(L("Écran verrouillé : touchez pour déverrouiller"))
                }
            }
            .padding(.horizontal, 6)
        }
        .foregroundColor(.white)
        .padding(.bottom, 6)
    }

    private func barButton(_ icon: String, _ title: String, active: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            barLabel(icon, title, active: active)
        }
    }

    private func barLabel(_ icon: String, _ title: String, active: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(active ? .brand : .white)
        .frame(minWidth: 52, minHeight: 40)
    }

    private var sleepLabel: String {
        if video.sleepAtEnd { return L("Minuterie : fin de la vidéo") }
        if let end = video.sleepEnd {
            let minutes = max(1, Int(ceil(end.timeIntervalSinceNow / 60)))
            return L("Minuterie : {n} min", ["n": "\(minutes)"])
        }
        return L("Minuterie")
    }

    private func speedText(_ value: Float) -> String {
        let text = value == Float(Int(value)) ? "\(Int(value))" : String(format: "%g", value)
        return text.replacingOccurrences(of: ".", with: Lang.code == "fr" ? "," : ".") + "×"
    }

    private func stepLabel(_ step: Double) -> String {
        if step == 0 { return L("Remettre à zéro") }
        let sign = step > 0 ? "+" : ""
        return sign + delayText(step) + " s"
    }

    private func delayText(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return Lang.code == "fr" ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    private func sizeName(_ size: Int) -> String {
        switch size {
        case 1: return L("Petit")
        case 3: return L("Grand")
        case 4: return L("Très grand")
        default: return L("Moyen")
        }
    }
}
