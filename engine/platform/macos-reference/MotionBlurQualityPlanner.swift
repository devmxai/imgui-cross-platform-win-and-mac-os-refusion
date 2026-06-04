import Foundation

struct MotionBlurSamplePlan {
    let samples: [(time: Double, weight: Double)]
    let maxPixelDisplacement: Double
    let sampleCount: Int
}

enum MotionBlurQualityPlanner {
    static func plan(
        pass: FXPassNode,
        node: RenderGraphNode,
        frameTime: Double,
        fps: Double,
        maxSamples: Int,
        nodeAtTime: (Double) -> RenderGraphNode?
    ) -> MotionBlurSamplePlan {
        let params = pass.params.objectValue ?? [:]
        let safeFPS = max(1, fps)
        let frameDuration = 1 / safeFPS
        let shutterAngle = min(1440, max(0, params["shutterAngle"]?.numberValue ?? (params["shutter"]?.numberValue ?? 1) * 180))
        let shutterPhase = min(720, max(-720, params["shutterPhase"]?.numberValue ?? -shutterAngle / 2))
        let amount = min(10, max(0, params["amount"]?.numberValue ?? params["strength"]?.numberValue ?? 1))
        let shutterDuration = frameDuration * shutterAngle / 360 * amount
        let centerTime = frameTime + frameDuration * shutterPhase / 360
        let start = max(0, centerTime - shutterDuration / 2)
        let end = max(start, centerTime + shutterDuration / 2)

        let requested = requestedSampleCount(params: params)
        let displacement = maxPixelDisplacement(
            reference: node,
            times: [start, start + shutterDuration * 0.25, centerTime, start + shutterDuration * 0.75, end],
            nodeAtTime: nodeAtTime
        )
        let adaptive = adaptiveSampleCount(displacement: displacement, shutterAngle: shutterAngle, amount: amount)
        let sampleCount = min(maxSamples, max(requested, adaptive, 2))
        let curve = params["sampleCurve"]?.stringValue ?? "filmic"
        let rawSamples = (0..<sampleCount).map { index -> (time: Double, weight: Double) in
            let progress = sampleCount == 1 ? 0.5 : Double(index) / Double(sampleCount - 1)
            let time = start + progress * (end - start)
            return (time, reconstructionWeight(progress: progress, curve: curve))
        }
        let total = max(0.0001, rawSamples.reduce(0) { $0 + $1.weight })
        return MotionBlurSamplePlan(
            samples: rawSamples.map { ($0.time, $0.weight / total) },
            maxPixelDisplacement: displacement,
            sampleCount: sampleCount
        )
    }

    private static func requestedSampleCount(params: [String: JSONValue]) -> Int {
        if let value = params["quality"]?.stringValue {
            switch value {
            case "draft": return 8
            case "preview": return 16
            case "high": return 48
            case "cinematic", "best", "ultra": return 96
            default: break
            }
        }
        return max(16, Int((params["samples"]?.numberValue ?? 24).rounded()))
    }

    private static func adaptiveSampleCount(displacement: Double, shutterAngle: Double, amount: Double) -> Int {
        let pixelsPerSample = 1.35
        let displacementSamples = Int(ceil(max(0, displacement) / pixelsPerSample))
        let shutterSamples = Int(ceil(max(0, shutterAngle * max(1, amount)) / 18))
        return max(displacementSamples, shutterSamples)
    }

    private static func maxPixelDisplacement(
        reference: RenderGraphNode,
        times: [Double],
        nodeAtTime: (Double) -> RenderGraphNode?
    ) -> Double {
        let referenceCorners = layerCorners(reference.transform)
        var displacement = 0.0
        for time in times {
            guard let sample = nodeAtTime(max(0, time)) else { continue }
            let sampleCorners = layerCorners(sample.transform)
            for index in 0..<min(referenceCorners.count, sampleCorners.count) {
                displacement = max(displacement, hypot(sampleCorners[index].x - referenceCorners[index].x, sampleCorners[index].y - referenceCorners[index].y))
            }
        }
        return displacement
    }

    private static func layerCorners(_ transform: RenderTransform) -> [(x: Double, y: Double)] {
        let centerX = transform.x + transform.width * transform.anchorX
        let centerY = transform.y + transform.height * transform.anchorY
        let left = -transform.width * transform.anchorX
        let right = transform.width * (1 - transform.anchorX)
        let top = -transform.height * transform.anchorY
        let bottom = transform.height * (1 - transform.anchorY)
        let radians = transform.rotationDegrees * .pi / 180
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        return [
            point(localX: left, localY: top, transform: transform, centerX: centerX, centerY: centerY, cosValue: cosValue, sinValue: sinValue),
            point(localX: right, localY: top, transform: transform, centerX: centerX, centerY: centerY, cosValue: cosValue, sinValue: sinValue),
            point(localX: right, localY: bottom, transform: transform, centerX: centerX, centerY: centerY, cosValue: cosValue, sinValue: sinValue),
            point(localX: left, localY: bottom, transform: transform, centerX: centerX, centerY: centerY, cosValue: cosValue, sinValue: sinValue)
        ]
    }

    private static func point(localX: Double, localY: Double, transform: RenderTransform, centerX: Double, centerY: Double, cosValue: Double, sinValue: Double) -> (x: Double, y: Double) {
        let skewedX = localX + tan(transform.skewXDegrees * .pi / 180) * localY
        let skewedY = tan(transform.skewYDegrees * .pi / 180) * localX + localY
        let scaledX = skewedX * transform.scaleX
        let scaledY = skewedY * transform.scaleY
        return (
            x: centerX + scaledX * cosValue - scaledY * sinValue,
            y: centerY + scaledX * sinValue + scaledY * cosValue
        )
    }

    private static func reconstructionWeight(progress: Double, curve: String) -> Double {
        switch curve {
        case "uniform":
            return 1
        case "centerWeighted":
            let distance = abs(progress - 0.5) * 2
            return max(0.01, 1 - distance * 0.55)
        default:
            let a0 = 0.35875
            let a1 = 0.48829
            let a2 = 0.14128
            let a3 = 0.01168
            let x = 2 * .pi * progress
            return max(0.001, a0 - a1 * cos(x) + a2 * cos(2 * x) - a3 * cos(3 * x))
        }
    }
}
