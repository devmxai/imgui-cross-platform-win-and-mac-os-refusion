import Foundation
import Metal

struct MetalFXResolvedTexture {
    let texture: MTLTexture
    let boundsScaleX: Double
    let boundsScaleY: Double
}

final class MetalFXRuntime {
    private let device: MTLDevice
    private let motionTilePipeline: MTLComputePipelineState
    private let radialBlurPipeline: MTLComputePipelineState

    init?(device: MTLDevice) {
        self.device = device
        do {
            let library = try device.makeLibrary(source: metalFXShaderSource, options: nil)
            guard
                let motionTile = library.makeFunction(name: "fx_motion_tile"),
                let radialBlur = library.makeFunction(name: "fx_radial_blur")
            else { return nil }
            self.motionTilePipeline = try device.makeComputePipelineState(function: motionTile)
            self.radialBlurPipeline = try device.makeComputePipelineState(function: radialBlur)
        } catch {
            NSLog("MetalFXRuntime pipeline creation failed: \(error.localizedDescription)")
            return nil
        }
    }

    func resolve(
        sourceTexture: MTLTexture,
        node: RenderGraphNode,
        fxGraph: FXPassGraphSnapshot,
        commandBuffer: MTLCommandBuffer,
        isLiveScrubbing: Bool = false,
        includePreTransform: Bool = true,
        includePostTransform: Bool = true
    ) -> MetalFXResolvedTexture {
        var current = sourceTexture
        var boundsScaleX = 1.0
        var boundsScaleY = 1.0

        let passes = fxGraph.passes
            .filter { $0.clipId == node.clipId && $0.status == .supported }
            .sorted { left, right in
                if left.category == right.category { return left.stageIndex < right.stageIndex }
                return passRank(left.category) < passRank(right.category)
            }

        for pass in passes {
            if pass.category == .preTransform && !includePreTransform { continue }
            if pass.category == .postTransform && !includePostTransform { continue }
            if pass.category == .temporal { continue }
            switch pass.effectName {
            case "motionTile":
                let result = applyMotionTile(sourceTexture: current, pass: pass, commandBuffer: commandBuffer)
                current = result.texture
                boundsScaleX *= result.boundsScaleX
                boundsScaleY *= result.boundsScaleY
            case "radialBlur", "zoomBlur", "spiralEchoBlur":
                current = applyRadialBlur(
                    sourceTexture: current,
                    pass: pass,
                    commandBuffer: commandBuffer,
                    sampleLimit: isLiveScrubbing ? 32 : 96
                ) ?? current
            default:
                continue
            }
        }

        return MetalFXResolvedTexture(
            texture: current,
            boundsScaleX: boundsScaleX,
            boundsScaleY: boundsScaleY
        )
    }

    private func applyRadialBlur(
        sourceTexture: MTLTexture,
        pass: FXPassNode,
        commandBuffer: MTLCommandBuffer,
        sampleLimit: Int
    ) -> MTLTexture? {
        let params = pass.params.objectValue ?? [:]
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard
            let outputTexture = device.makeTexture(descriptor: descriptor),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }

        var uniforms = MetalFXRadialBlurUniforms(
            center: SIMD2<Float>(
                Float(params["centerX"]?.numberValue ?? 0.5),
                Float(params["centerY"]?.numberValue ?? 0.5)
            ),
            amount: Float(clamp(params["amount"]?.numberValue ?? 1, min: 0, max: 10)),
            angleRadians: Float((params["angleDegrees"]?.numberValue ?? 18) * .pi / 180),
            zoomSpread: Float(clamp(params["zoomSpread"]?.numberValue ?? 0.08, min: -4, max: 4)),
            radialSpread: Float(clamp(params["radialSpread"]?.numberValue ?? 0.08, min: -4, max: 4)),
            samples: UInt32(min(sampleLimit, max(2, Int((params["samples"]?.numberValue ?? 24).rounded())))),
            mode: radialBlurMode(params["mode"]?.stringValue),
            curve: sampleCurveMode(params["sampleCurve"]?.stringValue)
        )

        encoder.setComputePipelineState(radialBlurPipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFXRadialBlurUniforms>.stride, index: 0)

        let width = radialBlurPipeline.threadExecutionWidth
        let height = max(1, radialBlurPipeline.maxTotalThreadsPerThreadgroup / width)
        let threadsPerGroup = MTLSize(width: width, height: height, depth: 1)
        let threads = MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        return outputTexture
    }

    private func applyMotionTile(
        sourceTexture: MTLTexture,
        pass: FXPassNode,
        commandBuffer: MTLCommandBuffer
    ) -> MetalFXResolvedTexture {
        let params = pass.params.objectValue ?? [:]
        let expansionX = clamp(params["expansionX"]?.numberValue ?? 1, min: 1, max: 64)
        let expansionY = clamp(params["expansionY"]?.numberValue ?? 1, min: 1, max: 64)
        let outputWidth = max(1, sourceTexture.width)
        let outputHeight = max(1, sourceTexture.height)

        guard expansionX > 1.0001 || expansionY > 1.0001 else {
            return MetalFXResolvedTexture(texture: sourceTexture, boundsScaleX: 1, boundsScaleY: 1)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: outputWidth,
            height: outputHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard
            let outputTexture = device.makeTexture(descriptor: descriptor),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return MetalFXResolvedTexture(texture: sourceTexture, boundsScaleX: 1, boundsScaleY: 1)
        }

        var uniforms = MetalFXMotionTileUniforms(
            expansion: SIMD2<Float>(Float(expansionX), Float(expansionY)),
            mode: motionTileMode(params["mode"]?.stringValue),
            _padding: 0
        )
        encoder.setComputePipelineState(motionTilePipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalFXMotionTileUniforms>.stride, index: 0)

        let width = motionTilePipeline.threadExecutionWidth
        let height = max(1, motionTilePipeline.maxTotalThreadsPerThreadgroup / width)
        let threadsPerGroup = MTLSize(width: width, height: height, depth: 1)
        let threads = MTLSize(width: outputWidth, height: outputHeight, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        return MetalFXResolvedTexture(
            texture: outputTexture,
            boundsScaleX: expansionX,
            boundsScaleY: expansionY
        )
    }

    private func motionTileMode(_ value: String?) -> UInt32 {
        switch value {
        case "repeat": return 1
        case "clamp": return 2
        default: return 0
        }
    }

    private func radialBlurMode(_ value: String?) -> UInt32 {
        switch value {
        case "radial": return 0
        case "zoom": return 2
        case "spiral": return 3
        default: return 1
        }
    }

    private func sampleCurveMode(_ value: String?) -> UInt32 {
        switch value {
        case "uniform": return 0
        case "filmic": return 2
        default: return 1
        }
    }

    private func passRank(_ category: FXPassCategory) -> Int {
        switch category {
        case .sourceResolve: return 0
        case .preTransform: return 1
        case .transform: return 2
        case .postTransform: return 3
        case .mask: return 4
        case .composite: return 5
        case .adjustment: return 6
        case .transition: return 7
        case .temporal: return 8
        case .audioReactive: return 9
        }
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}

private struct MetalFXMotionTileUniforms {
    var expansion: SIMD2<Float>
    var mode: UInt32
    var _padding: UInt32
}

private struct MetalFXRadialBlurUniforms {
    var center: SIMD2<Float>
    var amount: Float
    var angleRadians: Float
    var zoomSpread: Float
    var radialSpread: Float
    var samples: UInt32
    var mode: UInt32
    var curve: UInt32
}

private let metalFXShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct MetalFXMotionTileUniforms {
    float2 expansion;
    uint mode;
    uint _padding;
};

struct MetalFXRadialBlurUniforms {
    float2 center;
    float amount;
    float angleRadians;
    float zoomSpread;
    float radialSpread;
    uint samples;
    uint mode;
    uint curve;
};

float fx_repeat_coord(float value) {
    return fract(value);
}

float fx_mirror_coord(float value) {
    float repeated = fmod(value, 2.0);
    if (repeated < 0.0) {
        repeated += 2.0;
    }
    return repeated <= 1.0 ? repeated : 2.0 - repeated;
}

float2 fx_wrap_uv(float2 uv, uint mode) {
    if (mode == 1) {
        return float2(fx_repeat_coord(uv.x), fx_repeat_coord(uv.y));
    }
    if (mode == 2) {
        return clamp(uv, float2(0.0), float2(1.0));
    }
    return float2(fx_mirror_coord(uv.x), fx_mirror_coord(uv.y));
}

kernel void fx_motion_tile(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant MetalFXMotionTileUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 outputSize = float2(output.get_width(), output.get_height());
    float2 outputUV = (float2(gid) + 0.5) / outputSize;
    float2 sourceUV = (outputUV - 0.5) * max(uniforms.expansion, float2(1.0)) + 0.5;
    sourceUV = fx_wrap_uv(sourceUV, uniforms.mode);
    output.write(source.sample(linearSampler, sourceUV), gid);
}

float fx_sample_weight(float progress, uint curve) {
    float distanceFromCenter = abs(progress - 0.5) * 2.0;
    if (curve == 0) {
        return 1.0;
    }
    if (curve == 2) {
        return 0.5 + 0.5 * cos(distanceFromCenter * M_PI_F);
    }
    return max(0.05, 1.0 - distanceFromCenter * 0.65);
}

float2 fx_rotate(float2 value, float radians) {
    float c = cos(radians);
    float s = sin(radians);
    return float2(value.x * c - value.y * s, value.x * s + value.y * c);
}

kernel void fx_radial_blur(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant MetalFXRadialBlurUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 outputSize = float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) + 0.5) / outputSize;
    uint sampleCount = max(2u, min(96u, uniforms.samples));
    float2 center = uniforms.center;
    float2 delta = uv - center;
    float2 direction = length(delta) > 0.00001 ? normalize(delta) : float2(0.0, 0.0);
    float amount = max(0.0, uniforms.amount);
    float4 total = float4(0.0);
    float weightTotal = 0.0;

    for (uint i = 0; i < sampleCount; i++) {
        float progress = sampleCount == 1u ? 0.5 : float(i) / float(sampleCount - 1u);
        float signedProgress = (progress - 0.5) * 2.0;
        float2 sampleUV = uv;

        if (uniforms.mode == 1u || uniforms.mode == 3u) {
            float spin = signedProgress * uniforms.angleRadians * amount;
            sampleUV = center + fx_rotate(sampleUV - center, spin);
        }
        if (uniforms.mode == 2u || uniforms.mode == 3u) {
            float zoom = max(0.001, 1.0 + signedProgress * uniforms.zoomSpread * amount);
            sampleUV = center + (sampleUV - center) * zoom;
        }
        if (uniforms.mode == 0u || uniforms.mode == 3u) {
            sampleUV += direction * signedProgress * uniforms.radialSpread * amount;
        }

        float weight = fx_sample_weight(progress, uniforms.curve);
        total += source.sample(linearSampler, clamp(sampleUV, float2(0.0), float2(1.0))) * weight;
        weightTotal += weight;
    }

    output.write(total / max(weightTotal, 0.0001), gid);
}
"""
