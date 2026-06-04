import AppKit
import Metal
import MetalKit
import SwiftUI

struct NativeRenderSurface: NSViewRepresentable {
    @EnvironmentObject private var editor: EditorState

    func makeNSView(context: Context) -> MTKView {
        let view = StableNativeMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        editor.nativeRenderEngine.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        editor.nativeRenderEngine.loadProject(
            editor.linkedHyperFrameIR,
            workspaceURL: editor.workspaceURL,
            displayFrame: editor.currentFrame
        )
        editor.nativeRenderEngine.setViewportSize(nsView.drawableSize)
        editor.nativeRenderEngine.setTimelineObserver { [weak editor] frameIndex in
            Task { @MainActor in
                editor?.acceptRendererFrame(frameIndex)
            }
        }
    }

    final class StableNativeMTKView: MTKView {
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
    }
}
