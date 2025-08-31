import SwiftUI
import MetalKit
import Metal
import Combine

#if os(iOS)
import UIKit

struct MetalView: UIViewRepresentable {
    @StateObject private var renderer: MetalRendererWrapper
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        self._renderer = StateObject(wrappedValue: MetalRendererWrapper(device: device))
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device
        mtkView.delegate = renderer.metalRenderer
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        mtkView.addGestureRecognizer(pinchGesture)
        
        renderer.loadOBJFile()
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer.metalRenderer)
    }
    
    class Coordinator: NSObject {
        private let renderer: MetalRenderer
        private var lastPanLocation: CGPoint = .zero
        
        init(renderer: MetalRenderer) {
            self.renderer = renderer
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            if gesture.state == .began {
                lastPanLocation = location
            } else if gesture.state == .changed {
                let deltaX = Float(location.x - lastPanLocation.x)
                let deltaY = Float(location.y - lastPanLocation.y)
                
                if gesture.numberOfTouches == 1 {
                    renderer.rotate(deltaX: deltaX, deltaY: deltaY)
                }
                
                lastPanLocation = location
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .changed {
                let scale = Float(gesture.scale - 1.0)
                renderer.zoom(delta: scale)
                gesture.scale = 1.0
            }
        }
    }
}
#endif

class MetalRendererWrapper: ObservableObject {
    let device: MTLDevice
    let metalRenderer: MetalRenderer
    
    init(device: MTLDevice) {
        self.device = device
        self.metalRenderer = MetalRenderer(device: device)
    }
    
    func loadOBJFile() {
        guard let url = Bundle.main.url(forResource: "simple_cylinder", withExtension: "obj") else {
            print("Failed to find simple_cylinder.obj in bundle")
            return
        }
        
        do {
            let parser = OBJParser()
            let vertices = try parser.parseOBJ(from: url)
            metalRenderer.loadModel(vertices: vertices)
            print("Loaded \(vertices.count) vertices from OBJ file")
        } catch {
            print("Failed to load OBJ file: \(error)")
        }
    }
}

#if os(macOS)
import AppKit

struct MetalViewMacOS: NSViewRepresentable {
    @StateObject private var renderer: MetalRendererWrapper
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        self._renderer = StateObject(wrappedValue: MetalRendererWrapper(device: device))
    }
    
    func makeNSView(context: Context) -> TouchableMTKView {
        let mtkView = TouchableMTKView()
        mtkView.device = renderer.device
        mtkView.delegate = renderer.metalRenderer
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        
        mtkView.renderer = renderer.metalRenderer
        
        renderer.loadOBJFile()
        
        return mtkView
    }
    
    func updateNSView(_ nsView: TouchableMTKView, context: Context) {
    }
    
}

class TouchableMTKView: MTKView {
    var renderer: MetalRenderer?
    private var lastTouchLocation: CGPoint = .zero
    private var activeTouches: Set<NSTouch> = []
    private var lastMouseLocation: CGPoint = .zero
    private var isMouseDragging = false
    
    override func awakeFromNib() {
        super.awakeFromNib()
        allowedTouchTypes = [.direct, .indirect]
    }
    
    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        allowedTouchTypes = [.direct, .indirect]
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        allowedTouchTypes = [.direct, .indirect]
    }
    
    // Touch events for trackpad
    override func touchesBegan(with event: NSEvent) {
        let touches = event.touches(for: self)
        for touch in touches {
            // Only add touches that can provide location data
            if touch.type == .direct {
                activeTouches.insert(touch)
            }
        }
        
        if let firstTouch = touches.first(where: { $0.type == .direct }) {
            lastTouchLocation = firstTouch.location(in: self)
            renderer?.startRotation()
        }
    }
    
    override func touchesMoved(with event: NSEvent) {
        let touches = event.touches(for: self).filter { $0.type == .direct }
        
        if activeTouches.count == 1, let firstTouch = touches.first {
            let currentLocation = firstTouch.location(in: self)
            let deltaX = Float(currentLocation.x - lastTouchLocation.x)
            let deltaY = Float(currentLocation.y - lastTouchLocation.y)
            
            renderer?.rotate(deltaX: deltaX, deltaY: deltaY)
            lastTouchLocation = currentLocation
        }
        else if activeTouches.count == 2 {
            // Handle pinch gesture for zoom
            if touches.count >= 2 {
                let touchArray = Array(touches)
                let touch1 = touchArray[0].location(in: self)
                let touch2 = touchArray[1].location(in: self)
                
                let currentDistance = distance(touch1, touch2)
                
                // Store previous distance in a static variable for comparison
                struct PinchState {
                    static var previousDistance: CGFloat = 0
                }
                
                if PinchState.previousDistance > 0 {
                    let scale = Float((currentDistance - PinchState.previousDistance) / 100.0)
                    renderer?.zoom(delta: scale)
                }
                PinchState.previousDistance = currentDistance
            }
        }
    }
    
    override func touchesEnded(with event: NSEvent) {
        let touches = event.touches(for: self).filter { $0.type == .direct }
        for touch in touches {
            activeTouches.remove(touch)
        }
        
        if activeTouches.isEmpty {
            // Reset pinch state when all touches end
            struct PinchState {
                static var previousDistance: CGFloat = 0
            }
            PinchState.previousDistance = 0
            renderer?.endRotation()
        }
    }
    
    override func touchesCancelled(with event: NSEvent) {
        activeTouches.removeAll()
        struct PinchState {
            static var previousDistance: CGFloat = 0
        }
        PinchState.previousDistance = 0
    }
    
    // Mouse events for traditional mouse/trackpad
    override func mouseDown(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
        isMouseDragging = true
        renderer?.startRotation()
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isMouseDragging {
            let currentLocation = convert(event.locationInWindow, from: nil)
            let deltaX = Float(currentLocation.x - lastMouseLocation.x)
            let deltaY = Float(currentLocation.y - lastMouseLocation.y)
            
            renderer?.rotate(deltaX: deltaX, deltaY: deltaY)
            lastMouseLocation = currentLocation
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isMouseDragging = false
        renderer?.endRotation()
    }
    
    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        renderer?.zoom(delta: delta * 0.01)
    }
    
    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
}
#endif