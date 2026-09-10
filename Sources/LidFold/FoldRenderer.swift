import CoreVideo
import Metal
import MetalKit

@MainActor
final class FoldRenderer: NSObject, MTKViewDelegate {
    enum RendererError: LocalizedError {
        case commandQueueUnavailable
        case textureCacheCreationFailed(CVReturn)
        case shaderCompilationFailed(Error)
        case pipelineCreationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .commandQueueUnavailable:
                "Metal could not create a command queue."
            case let .textureCacheCreationFailed(status):
                "Metal could not create a Core Video texture cache (status \(status))."
            case let .shaderCompilationFailed(error):
                "Metal could not compile the pass-through shaders: \(error.localizedDescription)"
            case let .pipelineCreationFailed(error):
                "Metal could not create the pass-through render pipeline: \(error.localizedDescription)"
            }
        }
    }

    let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache
    private var currentTexture: MTLTexture?
    private var currentCoreVideoTexture: CVMetalTexture?
    private var currentPixelBuffer: CVPixelBuffer?
    private var uniforms = FoldUniforms(parameters: .map(angle: 180))

    init(device: MTLDevice) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard cacheStatus == kCVReturnSuccess, let cache else {
            throw RendererError.textureCacheCreationFailed(cacheStatus)
        }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw RendererError.shaderCompilationFailed(error)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "LidFold pass-through pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "lidFoldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "lidFoldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.pipelineCreationFailed(error)
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = cache
        self.pipelineState = pipelineState
        super.init()
    }

    /// Makes a complete BGRA frame available for the next draw.
    ///
    /// Returning `false` is deliberately fail-closed: callers must not reveal the
    /// overlay when Core Video cannot produce a usable Metal texture.
    @discardableResult
    func update(pixelBuffer: CVPixelBuffer, parameters: FoldParameters) -> Bool {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            clearFrame()
            return false
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            clearFrame()
            return false
        }

        var coreVideoTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &coreVideoTexture
        )
        guard
            status == kCVReturnSuccess,
            let coreVideoTexture,
            let texture = CVMetalTextureGetTexture(coreVideoTexture)
        else {
            clearFrame()
            return false
        }

        currentPixelBuffer = pixelBuffer
        currentCoreVideoTexture = coreVideoTexture
        currentTexture = texture
        uniforms = FoldUniforms(parameters: parameters)
        return true
    }

    func clearFrame() {
        currentTexture = nil
        currentCoreVideoTexture = nil
        currentPixelBuffer = nil
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    func draw(in view: MTKView) {
        guard
            let texture = currentTexture,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }

        commandBuffer.label = "LidFold pass-through frame"
        encoder.label = "LidFold pass-through encoder"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct RasterData {
            float4 position [[position]];
            float2 textureCoordinate;
        };

        struct FoldUniforms {
            float progress;
            float perspective;
            float blurRadius;
            float shadowOpacity;
        };

        vertex RasterData lidFoldVertex(uint vertexID [[vertex_id]]) {
            const float2 positions[] = {
                float2(-1.0, -1.0),
                float2( 3.0, -1.0),
                float2(-1.0,  3.0)
            };
            const float2 textureCoordinates[] = {
                float2(0.0,  1.0),
                float2(2.0,  1.0),
                float2(0.0, -1.0)
            };

            RasterData output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.textureCoordinate = textureCoordinates[vertexID];
            return output;
        }

        fragment float4 lidFoldFragment(
            RasterData input [[stage_in]],
            texture2d<float> frame [[texture(0)]],
            constant FoldUniforms& fold [[buffer(0)]]
        ) {
            constexpr sampler frameSampler(
                coord::normalized,
                address::clamp_to_edge,
                filter::linear
            );
            float2 outputUV = input.textureCoordinate;
            float top = 0.02 + 0.42 * fold.progress;
            float bottom = 1.0 - 0.01 * fold.progress;
            float sourceY = (outputUV.y - top) / max(bottom - top, 0.001);

            if (sourceY < 0.0 || sourceY > 1.0) {
                return float4(0.0, 0.0, 0.0, 1.0);
            }

            float topHalfWidth = 0.5 * (1.0 - 0.22 * fold.perspective);
            float halfWidth = mix(topHalfWidth, 0.5, sourceY);
            float centeredX = outputUV.x - 0.5;
            if (abs(centeredX) > halfWidth) {
                return float4(0.0, 0.0, 0.0, 1.0);
            }

            float2 sourceUV = float2(centeredX / (2.0 * halfWidth) + 0.5, sourceY);
            float2 texel = 1.0 / float2(frame.get_width(), frame.get_height());
            float2 radius = texel * fold.blurRadius;

            float4 color = frame.sample(frameSampler, sourceUV) * 0.28;
            color += frame.sample(frameSampler, sourceUV + float2(radius.x, 0.0)) * 0.12;
            color += frame.sample(frameSampler, sourceUV - float2(radius.x, 0.0)) * 0.12;
            color += frame.sample(frameSampler, sourceUV + float2(0.0, radius.y)) * 0.12;
            color += frame.sample(frameSampler, sourceUV - float2(0.0, radius.y)) * 0.12;
            color += frame.sample(frameSampler, sourceUV + radius) * 0.06;
            color += frame.sample(frameSampler, sourceUV - radius) * 0.06;
            color += frame.sample(frameSampler, sourceUV + float2(radius.x, -radius.y)) * 0.06;
            color += frame.sample(frameSampler, sourceUV + float2(-radius.x, radius.y)) * 0.06;

            float shade = 1.0 - fold.shadowOpacity * (1.0 - sourceY);
            color.rgb *= shade;
            color.a = 1.0;
            return color;
        }
        """
}

private struct FoldUniforms {
    var progress: Float
    var perspective: Float
    var blurRadius: Float
    var shadowOpacity: Float

    init(parameters: FoldParameters) {
        progress = Float(parameters.progress)
        perspective = Float(parameters.perspective)
        blurRadius = Float(parameters.blurRadius)
        shadowOpacity = Float(parameters.shadowOpacity)
    }
}
