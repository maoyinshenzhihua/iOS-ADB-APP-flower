import Foundation
import MetalKit
import CoreVideo

class ScreenRenderer: MTKView {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?
    private var viewportSize = CGSize.zero

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        setup()
    }

    private func setup() {
        guard let device = device else { return }

        commandQueue = device.makeCommandQueue()
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true

        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

        setupPipeline()
    }

    private func setupPipeline() {
        guard let device = device else { return }

        let vertexShader = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vid [[vertex_id]]) {
            float4 positions[4] = {
                float4(-1, -1, 0, 1),
                float4( 1, -1, 0, 1),
                float4(-1,  1, 0, 1),
                float4( 1,  1, 0, 1)
            };
            float2 texCoords[4] = {
                float2(0, 1),
                float2(1, 1),
                float2(0, 0),
                float2(1, 0)
            };
            VertexOut out;
            out.position = positions[vid];
            out.texCoord = texCoords[vid];
            return out;
        }
        """

        let fragmentShader = """
        #include <metal_stdlib>
        using namespace metal;

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                        texture2d<float, access::sample> tex [[texture(0)]]) {
            constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """

        let library = try? device.makeLibrary(source: vertexShader + fragmentShader, options: nil)
        guard let lib = library else {
            Logger.error("Metal着色器编译失败", category: "ScreenRenderer")
            return
        }

        let vertexFunc = lib.makeFunction(name: "vertexShader")
        let fragmentFunc = lib.makeFunction(name: "fragmentShader")

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            Logger.error("渲染管线创建失败: \(error)", category: "ScreenRenderer")
        }
    }

    func render(pixelBuffer: CVPixelBuffer) {
        guard let device = device, let textureCache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTex) else {
            return
        }

        currentTexture = texture
        viewportSize = CGSize(width: width, height: height)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let currentTexture = currentTexture,
              let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor else { return }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(currentTexture, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
