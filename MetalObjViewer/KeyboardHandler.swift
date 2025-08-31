import SwiftUI
import Combine

struct KeyboardHandler: View {
    let renderer: MetalRenderer
    @State private var keyState = Set<String>()
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .focusable()
            .onKeyPress { keyPress in
                _ = handleKeyPress(keyPress)
                return .handled
            }
            .onReceive(Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()) { _ in
                updateMovement()
            }
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let keyString = String(keyPress.key.character)
        
        if keyPress.phase == .down {
            keyState.insert(keyString)
        } else if keyPress.phase == .up {
            keyState.remove(keyString)
        }
        
        return .handled
    }
    
    private func updateMovement() {
        let moveSpeed: Float = 0.05
        var deltaX: Float = 0
        var deltaY: Float = 0
        
        if keyState.contains("←") {
            deltaX -= moveSpeed
        }
        if keyState.contains("→") {
            deltaX += moveSpeed
        }
        if keyState.contains("↑") {
            deltaY += moveSpeed
        }
        if keyState.contains("↓") {
            deltaY -= moveSpeed
        }
        
        if deltaX != 0 || deltaY != 0 {
            renderer.translate(deltaX: deltaX, deltaY: deltaY)
        }
    }
}

#if os(macOS)
import AppKit

class KeyboardResponder: NSResponder {
    private let renderer: MetalRenderer
    private var keyState = Set<UInt16>()
    private var timer: Timer?
    
    init(renderer: MetalRenderer) {
        self.renderer = renderer
        super.init()
        startTimer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        keyState.insert(event.keyCode)
    }
    
    override func keyUp(with event: NSEvent) {
        keyState.remove(event.keyCode)
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateMovement()
        }
    }
    
    private func updateMovement() {
        let moveSpeed: Float = 0.05
        var deltaX: Float = 0
        var deltaY: Float = 0
        
        if keyState.contains(123) {
            deltaX -= moveSpeed
        }
        if keyState.contains(124) {
            deltaX += moveSpeed
        }
        if keyState.contains(126) {
            deltaY += moveSpeed
        }
        if keyState.contains(125) {
            deltaY -= moveSpeed
        }
        
        if deltaX != 0 || deltaY != 0 {
            renderer.translate(deltaX: deltaX, deltaY: deltaY)
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
#endif