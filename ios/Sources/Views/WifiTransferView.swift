import SwiftUI

/// Écran « Transfert Wi-Fi » : l'adresse à taper dans le navigateur de l'ordinateur.
struct WifiTransferView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var transfer = WifiTransfer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(Color.brand.opacity(0.15))
                            .frame(width: 120, height: 120)
                        Image(systemName: transfer.running ? "wifi" : "wifi.slash")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(.brand)
                            .symbolEffectPulse(transfer.running)
                    }
                    .padding(.top, 20)

                    if let address = transfer.address, transfer.running {
                        VStack(spacing: 8) {
                            Text(L("Sur l'ordinateur (même Wi-Fi), ouvrez le navigateur et tapez :"))
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Text(address)
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.brand)
                                .textSelection(.enabled)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 18)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground)))
                            Button {
                                UIPasteboard.general.string = address
                                model.show(L("Adresse copiée."), .ok)
                            } label: {
                                Label(L("Copier l'adresse"), systemImage: "doc.on.doc")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                    } else if transfer.address == nil && transfer.running {
                        Text(L("Connectez l'iPhone à un réseau Wi-Fi."))
                            .foregroundColor(.orange)
                    } else if let error = transfer.error {
                        Text(error)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        step("1", L("L'iPhone et l'ordinateur doivent être sur le même Wi-Fi."))
                        step("2", L("Glissez vos vidéos, musiques, sous-titres ou un dossier entier dans la page."))
                        step("3", L("Gardez cet écran ouvert pendant l'envoi : les fichiers arrivent dans la Bibliothèque."))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))

                    if let current = transfer.current {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(L("Réception : {name}", ["name": current]))
                                .font(.system(size: 14))
                                .lineLimit(1)
                        }
                    }
                    if transfer.receivedCount > 0 {
                        Label(L("{count} fichier(s) reçu(s)", ["count": "\(transfer.receivedCount)"]),
                              systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .navigationTitle(L("Transfert Wi-Fi"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
        .onAppear {
            let appModel = model
            transfer.onReceived = { [weak appModel] in appModel?.rescan(force: true) }
            transfer.start()
        }
        .onDisappear {
            transfer.stop()
            model.rescan(force: true)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.brand))
            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    /// Petite animation de l'icône (iOS 17), rien sur iOS 16.
    @ViewBuilder
    func symbolEffectPulse(_ active: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, isActive: active)
        } else {
            self
        }
    }
}
