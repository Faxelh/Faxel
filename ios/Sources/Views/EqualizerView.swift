import SwiftUI

/// Égaliseur 10 bandes, préréglages, vitesse de lecture.
struct EqualizerView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle(isOn: Binding(
                        get: { player.eqEnabled },
                        set: { player.setEqualizer(enabled: $0) }
                    )) {
                        Label(L("Égaliseur"), systemImage: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(.brand)
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Préréglages").uppercased())
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(AudioPlayer.presets, id: \.id) { preset in
                                    Button {
                                        player.applyPreset(preset.id)
                                    } label: {
                                        Text(presetName(preset.id, fallback: preset.name))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(player.eqPreset == preset.id ? .white : .primary)
                                            .padding(.horizontal, 16)
                                            .frame(height: 34)
                                            .background(Capsule().fill(player.eqPreset == preset.id ? Color.brand
                                                                       : Color(.tertiarySystemFill)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(Array(player.eqGains.enumerated()), id: \.offset) { offset, gain in
                            VStack(spacing: 6) {
                                Text(gain > 0 ? "+\(Int(gain))" : "\(Int(gain))")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundColor(.secondary)
                                EqBandSlider(value: Binding(
                                    get: { gain },
                                    set: { player.setGain($0, band: offset) }
                                ))
                                .frame(height: 150)
                                Text(bandLabel(offset))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .opacity(player.eqEnabled ? 1 : 0.35)
                    .disabled(!player.eqEnabled)
                }
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .navigationTitle(L("Égaliseur"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bandLabel(_ offset: Int) -> String {
        let hz = AudioPlayer.bandFrequencies[offset]
        return hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))"
    }

    private func presetName(_ id: String, fallback: String) -> String {
        switch id {
        case "flat": return L("Neutre")
        case "bass": return L("Basses+")
        case "superbass": return L("Super basses")
        case "treble": return L("Aigus+")
        case "vocal": return L("Voix")
        case "pop": return L("Pop")
        case "rock": return L("Rock")
        case "hiphop": return L("Hip-hop")
        case "electro": return L("Électro")
        case "jazz": return L("Jazz")
        case "classical": return L("Classique")
        case "acoustic": return L("Acoustique")
        case "night": return L("Nuit (doux)")
        default: return fallback
        }
    }
}

/// Curseur vertical pour une bande de l'égaliseur.
struct EqBandSlider: View {
    @Binding var value: Float
    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let progress = CGFloat((value + 12) / 24)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(Color.brand)
                    .frame(height: max(6, height * progress))
            }
            .frame(width: 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStart == nil { dragStart = value }
                        let ratio = 1 - Float(drag.location.y / height)
                        value = max(-12, min(12, ratio * 24 - 12))
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
    }
}

/// Barres du spectre sonore (visualiseur), alimentées par AudioPlayer.meter.
struct SpectrumBarsView: View {
    @ObservedObject var meter: SpectrumMeter
    var color: Color = .white

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(sampled.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.25 + Double(value) * 0.75))
                        .frame(height: max(3, CGFloat(value) * geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }

    /// Réduit le nombre de bandes pour un affichage léger.
    private var sampled: [Float] {
        let spectrum = meter.spectrum
        let count = 24
        guard spectrum.count > count else { return spectrum }
        let step = spectrum.count / count
        return stride(from: 0, to: spectrum.count, by: max(1, step)).map { spectrum[$0] }
    }
}
