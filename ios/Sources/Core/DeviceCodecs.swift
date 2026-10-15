import CoreMedia
import VideoToolbox

/// Ce que l'iPhone sait décoder lui-même (pour choisir la meilleure qualité possible).
enum DeviceCodecs {
    /// AV1 (YouTube en 1440p / 2160p) : iPhone 15 Pro et plus récents, iPad M1 et plus récents.
    static let av1Supported: Bool = {
        let av1 = CMVideoCodecType(0x6176_3031) // « av01 »
        return VTIsHardwareDecodeSupported(av1)
    }()
}
