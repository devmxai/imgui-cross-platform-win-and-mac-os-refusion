import CoreMedia
import Foundation
import Metal
import VideoToolbox

struct NativeHardwareExportCapability {
    let metalDevice: any MTLDevice
    let metalDeviceName: String
    let metalRegistryID: UInt64
    let encoderID: String
    let encoderName: String
    let encoderGPURegistryID: UInt64?
    let codecName: String

    var encoderSpecification: [String: Any] {
        [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_EncoderID as String: encoderID
        ]
    }
}

enum NativeHardwareExportGate {
    static func requireH264(width: Int, height: Int) throws -> NativeHardwareExportCapability {
        let devices = MTLCopyAllDevices().sorted(by: isStrongerMetalDevice)
        guard !devices.isEmpty else {
            throw NativeExportError.hardwareMetalDeviceUnavailable
        }

        let encoders = try hardwareEncoders(codecType: kCMVideoCodecType_H264)
        guard !encoders.isEmpty else {
            throw NativeExportError.hardwareVideoEncoderUnavailable(codec: "H.264")
        }

        var lastProbeError: Error?
        for device in devices {
            let candidates = encoders
                .filter { $0.gpuRegistryID == device.registryID || $0.gpuRegistryID == nil }
                .sorted(by: isStrongerEncoder)
            for encoder in candidates {
                let capability = NativeHardwareExportCapability(
                    metalDevice: device,
                    metalDeviceName: device.name,
                    metalRegistryID: device.registryID,
                    encoderID: encoder.id,
                    encoderName: encoder.name,
                    encoderGPURegistryID: encoder.gpuRegistryID,
                    codecName: encoder.codecName
                )
                do {
                    try proveHardwareEncoder(capability, width: width, height: height)
                    return capability
                } catch {
                    lastProbeError = error
                }
            }
        }

        if let lastProbeError { throw lastProbeError }
        throw NativeExportError.hardwareEncoderNotAssociatedWithMetalDevice
    }

    private struct HardwareEncoder {
        let id: String
        let name: String
        let codecName: String
        let gpuRegistryID: UInt64?
        let performanceRating: Double
        let qualityRating: Double
    }

    private static func hardwareEncoders(codecType: CMVideoCodecType) throws -> [HardwareEncoder] {
        var rawEncoders: CFArray?
        let status = VTCopyVideoEncoderList(nil, &rawEncoders)
        guard status == noErr, let dictionaries = rawEncoders as? [[String: Any]] else {
            throw NativeExportError.hardwareEncoderEnumerationFailed(status)
        }
        return dictionaries.compactMap { dictionary in
            guard
                (dictionary[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == codecType,
                (dictionary[kVTVideoEncoderList_IsHardwareAccelerated as String] as? NSNumber)?.boolValue == true,
                let id = dictionary[kVTVideoEncoderList_EncoderID as String] as? String
            else {
                return nil
            }
            return HardwareEncoder(
                id: id,
                name: dictionary[kVTVideoEncoderList_DisplayName as String] as? String ?? id,
                codecName: dictionary[kVTVideoEncoderList_CodecName as String] as? String ?? "H.264",
                gpuRegistryID: (dictionary[kVTVideoEncoderList_GPURegistryID as String] as? NSNumber)?.uint64Value,
                performanceRating: (dictionary[kVTVideoEncoderList_PerformanceRating as String] as? NSNumber)?.doubleValue ?? 0,
                qualityRating: (dictionary[kVTVideoEncoderList_QualityRating as String] as? NSNumber)?.doubleValue ?? 0
            )
        }
    }

    private static func proveHardwareEncoder(
        _ capability: NativeHardwareExportCapability,
        width: Int,
        height: Int
    ) throws {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: capability.encoderSpecification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw NativeExportError.hardwareEncoderProbeFailed(status)
        }
        defer { VTCompressionSessionInvalidate(session) }

        var property: CFTypeRef?
        let propertyStatus = withUnsafeMutablePointer(to: &property) { pointer in
            VTSessionCopyProperty(
                session,
                key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                allocator: kCFAllocatorDefault,
                valueOut: UnsafeMutableRawPointer(pointer)
            )
        }
        guard
            propertyStatus == noErr,
            let number = property as? NSNumber,
            number.boolValue
        else {
            throw NativeExportError.hardwareEncoderProofRejected(propertyStatus)
        }
    }

    private static func isStrongerMetalDevice(_ lhs: any MTLDevice, _ rhs: any MTLDevice) -> Bool {
        deviceScore(lhs) > deviceScore(rhs)
    }

    private static func isStrongerEncoder(_ lhs: HardwareEncoder, _ rhs: HardwareEncoder) -> Bool {
        if lhs.performanceRating != rhs.performanceRating {
            return lhs.performanceRating > rhs.performanceRating
        }
        return lhs.qualityRating > rhs.qualityRating
    }

    private static func deviceScore(_ device: any MTLDevice) -> UInt64 {
        var score = device.recommendedMaxWorkingSetSize
        if !device.isLowPower { score += 1 << 62 }
        if device.isRemovable { score += 1 << 61 }
        return score
    }
}
