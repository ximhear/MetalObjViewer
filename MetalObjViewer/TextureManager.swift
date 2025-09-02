import Metal
import MetalKit
import Foundation

class TextureManager {
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    private var textureCache: [String: MTLTexture] = [:]
    
    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    func loadTexture(named name: String) -> MTLTexture? {
        if let cachedTexture = textureCache[name] {
            return cachedTexture
        }
        
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            print("Texture file not found: \(name)")
            return createDefaultTexture()
        }
        
        do {
            let texture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
            ])
            
            textureCache[name] = texture
            return texture
        } catch {
            print("Failed to load texture \(name): \(error)")
            return createDefaultTexture()
        }
    }
    
    private func createDefaultTexture() -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        #if os(iOS)
            textureDescriptor.storageMode = .private
        #else
            textureDescriptor.storageMode = .managed
        #endif
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }
        
        let whitePixel: [UInt8] = [255, 255, 255, 255]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: whitePixel,
            bytesPerRow: 4
        )
        
        return texture
    }
}
