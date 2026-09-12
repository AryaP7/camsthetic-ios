import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Phase 2.0 — Capture Fidelity Proof: JSON sidecar model (THROWAWAY)
//
// Codable description of everything IMPLEMENTATION_PLAN.md Phase 2.0 / the user's
// request asks this proof to record for each trial. See
// CaptureFidelityProofHarness.swift for how this is populated and written.
//
// `ImageArtifactIntrospection` reads back the exact bytes already saved from
// `AVCapturePhoto.fileDataRepresentation()` using ImageIO, purely to describe them
// in the sidecar (container, dimensions, bit depth, ICC profile, auxiliary images).
// This is read-only inspection — it never modifies, re-encodes, or regenerates the
// saved file.

struct CaptureFidelitySidecar: Codable {
    let trial: String
    let trialLabel: String
    let timestampISO8601: String
    let captureLatencySeconds: Double
    let sessionPreset: String
    let device: DeviceInfo
    let activeFormat: FormatInfo
    let activeColorSpace: String
    let photoOutputConfiguration: PhotoOutputConfig
    let requestedPhotoSettings: RequestedSettingsInfo
    let resolvedPhotoSettings: ResolvedSettingsInfo
    let capturedPhotoMetadata: AnyCodable
    let fileByteCount: Int
    let fileSHA256Hex: String
    let imageIntrospection: ImageArtifactIntrospection
    let videoDataOutput: VideoOutputInfo
    let frameCounterAtCaptureTime: Int
    /// Automatically-generated observations (requested-vs-resolved mismatches,
    /// container type, low-frame-count warnings). Not a substitute for actually
    /// diffing the three trials' sidecars against each other.
    let notes: [String]
}

// MARK: - Device

struct DeviceInfo: Codable {
    let localizedName: String?
    let uniqueID: String?
    let modelID: String?
    let deviceType: String?
    let position: String?
    let isVirtualDevice: Bool?
    let constituentDeviceLocalizedNames: [String]?

    init(device: AVCaptureDevice?) {
        localizedName = device?.localizedName
        uniqueID = device?.uniqueID
        modelID = device?.modelID
        deviceType = device?.deviceType.rawValue
        position = device.map(Self.describe)
        isVirtualDevice = device?.isVirtualDevice
        constituentDeviceLocalizedNames = device?.constituentDevices.map(\.localizedName)
    }

    private static func describe(_ device: AVCaptureDevice) -> String {
        switch device.position {
        case .back: return "back"
        case .front: return "front"
        case .unspecified: return "unspecified"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Active format

struct FormatInfo: Codable {
    let formatDescription: String?
    let videoFieldOfViewDegrees: Float?
    let geometricDistortionCorrectedVideoFieldOfViewDegrees: Float?
    let supportedMaxPhotoDimensions: [String]
    let isHighPhotoQualitySupported: Bool?
    let isHighestPhotoQualitySupported: Bool?
    let supportedColorSpaces: [String]

    init(format: AVCaptureDevice.Format?) {
        formatDescription = format.map { String(describing: $0.formatDescription) }
        videoFieldOfViewDegrees = format?.videoFieldOfView
        geometricDistortionCorrectedVideoFieldOfViewDegrees = format?.geometricDistortionCorrectedVideoFieldOfView
        supportedMaxPhotoDimensions = (format?.supportedMaxPhotoDimensions ?? []).map(Self.describeDimensions)
        isHighPhotoQualitySupported = format?.isHighPhotoQualitySupported
        isHighestPhotoQualitySupported = format?.isHighestPhotoQualitySupported
        supportedColorSpaces = (format?.supportedColorSpaces ?? []).map(Self.describe)
    }

    static func describeDimensions(_ dimensions: CMVideoDimensions) -> String {
        "\(dimensions.width)x\(dimensions.height)"
    }

    static func describe(_ colorSpace: AVCaptureColorSpace?) -> String {
        guard let colorSpace else { return "unknown" }
        switch colorSpace {
        case .sRGB: return "sRGB"
        case .P3_D65: return "P3_D65"
        case .HLG_BT2020: return "HLG_BT2020"
        case .appleLog: return "appleLog"
        case .appleLog2: return "appleLog2"
        @unknown default: return "unknown(\(colorSpace.rawValue))"
        }
    }
}

// MARK: - Photo output configuration

struct PhotoOutputConfig: Codable {
    let maxPhotoQualityPrioritization: String
    let maxPhotoDimensions: String
    let availablePhotoCodecTypes: [String]
    let isVirtualDeviceConstituentPhotoDeliverySupported: Bool
    let isVirtualDeviceConstituentPhotoDeliveryEnabled: Bool
    let isZeroShutterLagSupported: Bool
    let isZeroShutterLagEnabled: Bool
    let isResponsiveCaptureSupported: Bool
    let isResponsiveCaptureEnabled: Bool
    let isFastCapturePrioritizationSupported: Bool
    let isFastCapturePrioritizationEnabled: Bool
    /// iOS 18+ only; nil on this proof's iOS 17 deployment target path when the
    /// runtime is below 18. Deliberately never enabled either way (see file header
    /// of CaptureFidelityProofHarness.swift).
    let isConstantColorSupported: Bool?
    let isConstantColorEnabled: Bool?

    init(output: AVCapturePhotoOutput) {
        maxPhotoQualityPrioritization = Self.describe(output.maxPhotoQualityPrioritization)
        maxPhotoDimensions = FormatInfo.describeDimensions(output.maxPhotoDimensions)
        availablePhotoCodecTypes = output.availablePhotoCodecTypes.map(\.rawValue)
        isVirtualDeviceConstituentPhotoDeliverySupported = output.isVirtualDeviceConstituentPhotoDeliverySupported
        isVirtualDeviceConstituentPhotoDeliveryEnabled = output.isVirtualDeviceConstituentPhotoDeliveryEnabled
        isZeroShutterLagSupported = output.isZeroShutterLagSupported
        isZeroShutterLagEnabled = output.isZeroShutterLagEnabled
        isResponsiveCaptureSupported = output.isResponsiveCaptureSupported
        isResponsiveCaptureEnabled = output.isResponsiveCaptureEnabled
        isFastCapturePrioritizationSupported = output.isFastCapturePrioritizationSupported
        isFastCapturePrioritizationEnabled = output.isFastCapturePrioritizationEnabled
        if #available(iOS 18.0, *) {
            isConstantColorSupported = output.isConstantColorSupported
            isConstantColorEnabled = output.isConstantColorEnabled
        } else {
            isConstantColorSupported = nil
            isConstantColorEnabled = nil
        }
    }

    static func describe(_ prioritization: AVCapturePhotoOutput.QualityPrioritization) -> String {
        switch prioritization {
        case .speed: return "speed"
        case .balanced: return "balanced"
        case .quality: return "quality"
        @unknown default: return "unknown(\(prioritization.rawValue))"
        }
    }
}

// MARK: - Requested / resolved settings

struct RequestedSettingsInfo: Codable {
    let uniqueID: Int64
    let requestedCodec: String
    let requestedMaxPhotoDimensions: String
    let photoQualityPrioritization: String
}

struct ResolvedSettingsInfo: Codable {
    let uniqueID: Int64
    let photoDimensions: String
    let previewDimensions: String
    let expectedPhotoCount: Int

    init(resolved: AVCaptureResolvedPhotoSettings) {
        uniqueID = resolved.uniqueID
        photoDimensions = FormatInfo.describeDimensions(resolved.photoDimensions)
        previewDimensions = FormatInfo.describeDimensions(resolved.previewDimensions)
        expectedPhotoCount = resolved.expectedPhotoCount
    }
}

// MARK: - Video data output (Trials A/B only)

struct VideoOutputInfo: Codable {
    let attached: Bool
    let delegateActive: Bool
    let alwaysDiscardsLateVideoFrames: Bool?
    let videoSettingsDescription: String?

    init(output: AVCaptureVideoDataOutput?, trial: CaptureFidelityTrial) {
        attached = output != nil
        delegateActive = trial == .a
        alwaysDiscardsLateVideoFrames = output?.alwaysDiscardsLateVideoFrames
        videoSettingsDescription = output.map { String(describing: $0.videoSettings) }
    }
}

// MARK: - Read-only introspection of the saved photo bytes (ImageIO)

struct ImageArtifactIntrospection: Codable {
    let containerUTI: String?
    let preferredFileExtension: String
    let imageCount: Int
    let pixelWidth: Int?
    let pixelHeight: Int?
    let bitDepth: Int?
    let colorModel: String?
    let iccProfileName: String?
    let hasAlpha: Bool?
    let dpiWidth: Double?
    let dpiHeight: Double?
    let hasDepthAuxiliary: Bool
    let hasDisparityAuxiliary: Bool
    let hasHDRGainMapAuxiliary: Bool
    let hasPortraitEffectsMatteAuxiliary: Bool

    /// Reads back the exact bytes just written by
    /// `AVCapturePhoto.fileDataRepresentation()` via ImageIO, purely to describe
    /// them for the sidecar. This does NOT re-encode, resize, tone-map, or
    /// otherwise transform the saved file — it is inspection only.
    init(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            containerUTI = nil
            preferredFileExtension = "bin"
            imageCount = 0
            pixelWidth = nil
            pixelHeight = nil
            bitDepth = nil
            colorModel = nil
            iccProfileName = nil
            hasAlpha = nil
            dpiWidth = nil
            dpiHeight = nil
            hasDepthAuxiliary = false
            hasDisparityAuxiliary = false
            hasHDRGainMapAuxiliary = false
            hasPortraitEffectsMatteAuxiliary = false
            return
        }

        let uti = CGImageSourceGetType(source) as String?
        containerUTI = uti
        if let uti, let type = UTType(uti) {
            preferredFileExtension = type.preferredFilenameExtension ?? "bin"
        } else {
            preferredFileExtension = "bin"
        }

        imageCount = CGImageSourceGetCount(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int
        pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int
        bitDepth = properties?[kCGImagePropertyDepth] as? Int
        colorModel = properties?[kCGImagePropertyColorModel] as? String
        iccProfileName = properties?[kCGImagePropertyProfileName] as? String
        hasAlpha = properties?[kCGImagePropertyHasAlpha] as? Bool
        dpiWidth = properties?[kCGImagePropertyDPIWidth] as? Double
        dpiHeight = properties?[kCGImagePropertyDPIHeight] as? Double

        func hasAuxiliary(_ type: CFString) -> Bool {
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) != nil
        }
        hasDepthAuxiliary = hasAuxiliary(kCGImageAuxiliaryDataTypeDepth)
        hasDisparityAuxiliary = hasAuxiliary(kCGImageAuxiliaryDataTypeDisparity)
        hasHDRGainMapAuxiliary = hasAuxiliary(kCGImageAuxiliaryDataTypeHDRGainMap)
        hasPortraitEffectsMatteAuxiliary = hasAuxiliary(kCGImageAuxiliaryDataTypePortraitEffectsMatte)
    }
}

// MARK: - Best-effort JSON encoding of arbitrary AVCapturePhoto.metadata values

/// `AVCapturePhoto.metadata` is `[String: Any]` (CGImageProperties-keyed: EXIF,
/// TIFF, orientation, Live Photo info, etc.), with arbitrary nesting. This wrapper
/// encodes it into the JSON sidecar on a best-effort basis. It is a diagnostic
/// artifact, not a re-encoding of the photo — an NSNumber whose Bool/Int/Double
/// identity is ambiguous (a well-known Foundation bridging quirk) may render as
/// the "wrong" numeric JSON type; every other case round-trips faithfully, and
/// anything genuinely unencodable falls back to its debug description string
/// rather than throwing.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        // Sidecars are write-only artifacts for this proof; decoding is not needed.
        let container = try decoder.singleValueContainer()
        value = (try? container.decode(String.self)) ?? "unsupported"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try Self.encode(value, into: &container)
    }

    private static func encode(_ value: Any, into container: inout SingleValueEncodingContainer) throws {
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Int64:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as Float:
            try container.encode(Double(v))
        case let v as String:
            try container.encode(v)
        case let v as NSNumber:
            try container.encode(v.doubleValue)
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyCodable($0) })
        case let v as NSDictionary:
            var dict: [String: AnyCodable] = [:]
            for (key, val) in v { dict["\(key)"] = AnyCodable(val) }
            try container.encode(dict)
        case let v as [Any]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as NSArray:
            try container.encode(v.map { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}
