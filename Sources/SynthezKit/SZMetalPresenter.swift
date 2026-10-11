//
//  SZMetalPresenter.swift
//  SynthezKit
//

#if canImport(UIKit)
    import Metal
    import QuartzCore
    import SynthezCore

    /// Puts an indexed ``SZSurface`` on screen.
    ///
    /// The surface is uploaded as an `r8Uint` texture and looked up in the
    /// palette on the GPU. Without CRT, it is scaled with "sharp bilinear"
    /// filtering, which blends only across the one device pixel straddling a
    /// virtual pixel edge, so fractional scales stay crisp.
    ///
    /// With CRT, every frame runs, in linear light:
    /// 1. phosphor: the new frame or the previous light times its decay,
    ///    whichever is brighter, per channel (afterglow);
    /// 2. halation: a half-size mip chain blurred down and added back up;
    /// 3. present: Gaussian beams over neighbouring scanlines whose width
    ///    grows with brightness, a shadow mask, the glow, a vignette and
    ///    glass reflection, then sRGB encoding.
    ///
    /// Three index textures rotate so the CPU never writes one the GPU is
    /// still reading; when all three are in flight the frame is dropped
    /// instead of blocking the main thread.
    @MainActor
    final class SZMetalPresenter {
        let device: MTLDevice
        private let queue: MTLCommandQueue
        private let plainPipeline: MTLRenderPipelineState
        private let phosphorPipeline: MTLRenderPipelineState
        private let downPipeline: MTLRenderPipelineState
        private let upPipeline: MTLRenderPipelineState
        private let presentPipeline: MTLRenderPipelineState
        private let paletteBuffer: MTLBuffer
        private var paletteVersion: UInt64 = 0
        private var indexTextures: [MTLTexture] = []
        private var indexSlot = 0
        private var lights: [MTLTexture] = []
        private var lightSlot = 0
        private var lightNeedsClear = true
        private var bloom: [MTLTexture] = []
        private let inFlight = DispatchSemaphore(value: 3)

        private struct PlainUniforms {
            var size: SIMD2<Float>
            var scale: Float
            var padding: Float = 0
        }

        private struct PhosphorUniforms {
            var decay: SIMD4<Float>
        }

        private struct CRTUniforms {
            var size: SIMD2<Float>
            var scale: Float
            var scanlines: Float
            var beamDim: Float
            var beamBright: Float
            var maskStrength: Float
            var maskType: Int32
            var halation: Float
            var vignette: Float
            var brightness: Float
            var ambient: Float
            var bloomLevels: Float
            var padding: Float = 0
        }

        init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
            guard let device, let queue = device.makeCommandQueue() else { return nil }
            guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) else { return nil }
            func pipeline(_ fragment: String, format: MTLPixelFormat, additive: Bool = false) -> MTLRenderPipelineState? {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "sz_vertex")
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
                descriptor.colorAttachments[0].pixelFormat = format
                if additive {
                    let attachment = descriptor.colorAttachments[0]!
                    attachment.isBlendingEnabled = true
                    attachment.rgbBlendOperation = .add
                    attachment.alphaBlendOperation = .add
                    attachment.sourceRGBBlendFactor = .one
                    attachment.destinationRGBBlendFactor = .one
                    attachment.sourceAlphaBlendFactor = .one
                    attachment.destinationAlphaBlendFactor = .one
                }
                return try? device.makeRenderPipelineState(descriptor: descriptor)
            }
            guard let plain = pipeline("sz_plain", format: .bgra8Unorm),
                  let phosphor = pipeline("sz_phosphor", format: .rgba16Float),
                  let down = pipeline("sz_down", format: .rgba16Float),
                  let up = pipeline("sz_up", format: .rgba16Float, additive: true),
                  let present = pipeline("sz_present", format: .bgra8Unorm),
                  let paletteBuffer = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * 256)
            else { return nil }
            self.device = device
            self.queue = queue
            plainPipeline = plain
            phosphorPipeline = phosphor
            downPipeline = down
            upPipeline = up
            presentPipeline = present
            self.paletteBuffer = paletteBuffer
        }

        func configure(_ layer: CAMetalLayer) {
            layer.device = device
            layer.pixelFormat = .bgra8Unorm
            layer.framebufferOnly = true
            layer.maximumDrawableCount = 3
        }

        /// Returns false when the frame was dropped; present again later.
        ///
        /// - Parameters:
        ///   - upload: Whether the surface changed since the last present.
        ///   - dt: Seconds since the last present, for the afterglow.
        func present(_ surface: SZSurface, upload: Bool, palette: SZPalette, screen: SZScreen, crt: SZCRTSettings, dt: Double, to layer: CAMetalLayer) -> Bool {
            guard surface.width > 0, surface.height > 0 else { return true }
            guard inFlight.wait(timeout: .now()) == .success else { return false }
            var committed = false
            defer {
                if !committed {
                    inFlight.signal()
                }
            }

            uploadPalette(palette)
            let texture = indexTexture(for: surface, upload: upload)
            guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return false }

            if crt.isEnabled {
                encodeCRT(surface: surface, texture: texture, screen: screen, crt: crt, dt: dt, drawable: drawable, into: buffer)
            } else {
                lightNeedsClear = true
                guard let encoder = buffer.makeRenderCommandEncoder(descriptor: Self.pass(drawable.texture, clear: true)) else { return false }
                encoder.setViewport(Self.viewport(screen))
                encoder.setRenderPipelineState(plainPipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 0)
                var uniforms = PlainUniforms(size: SIMD2(Float(surface.width), Float(surface.height)), scale: Float(screen.scale))
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PlainUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }

            let semaphore = inFlight
            buffer.addCompletedHandler { _ in semaphore.signal() }
            buffer.present(drawable)
            buffer.commit()
            committed = true
            return true
        }

        private func encodeCRT(surface: SZSurface, texture: MTLTexture, screen: SZScreen, crt: SZCRTSettings, dt: Double, drawable: CAMetalDrawable, into buffer: MTLCommandBuffer) {
            prepareCRTTargets(width: surface.width, height: surface.height, levels: min(max(crt.spread, 1), 6))
            let previous = lights[lightSlot]
            lightSlot ^= 1
            let current = lights[lightSlot]

            // 1. Phosphor.
            if let encoder = buffer.makeRenderCommandEncoder(descriptor: Self.pass(current, clear: true)) {
                encoder.setRenderPipelineState(phosphorPipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentTexture(previous, index: 1)
                encoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 0)
                // Red phosphor lingers longest; green and blue fade faster.
                let tau = max(crt.persistence, 0.0001)
                func decay(_ factor: Double) -> Float {
                    lightNeedsClear ? 0 : Float(exp(-dt / (tau * factor)))
                }
                // w = 0 marks the previous light as undefined (first frame).
                var uniforms = PhosphorUniforms(decay: SIMD4(decay(1), decay(0.7), decay(0.5), lightNeedsClear ? 0 : 1))
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PhosphorUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
            lightNeedsClear = false

            // 2. Halation: blur down the chain, then add each level back up.
            var source = current
            for level in bloom {
                guard let encoder = buffer.makeRenderCommandEncoder(descriptor: Self.pass(level, clear: true)) else { continue }
                encoder.setRenderPipelineState(downPipeline)
                encoder.setFragmentTexture(source, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                source = level
            }
            if bloom.count > 1 {
                for i in stride(from: bloom.count - 1, to: 0, by: -1) {
                    guard let encoder = buffer.makeRenderCommandEncoder(descriptor: Self.pass(bloom[i - 1], clear: false)) else { continue }
                    encoder.setRenderPipelineState(upPipeline)
                    encoder.setFragmentTexture(bloom[i], index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    encoder.endEncoding()
                }
            }

            // 3. Present.
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: Self.pass(drawable.texture, clear: true)) else { return }
            encoder.setViewport(Self.viewport(screen))
            encoder.setRenderPipelineState(presentPipeline)
            encoder.setFragmentTexture(current, index: 0)
            encoder.setFragmentTexture(bloom.first ?? current, index: 1)
            var uniforms = CRTUniforms(
                size: SIMD2(Float(surface.width), Float(surface.height)),
                scale: Float(screen.scale),
                scanlines: Float(crt.scanlines),
                beamDim: Float(crt.beamDim),
                beamBright: Float(crt.beamBright),
                maskStrength: Float(crt.maskStrength),
                maskType: Int32(crt.mask.rawValue),
                halation: Float(crt.halation),
                vignette: Float(crt.vignette),
                brightness: Float(crt.brightness),
                ambient: Float(crt.ambient),
                bloomLevels: Float(max(bloom.count, 1)),
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CRTUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // MARK: - Resources

        private static func pass(_ texture: MTLTexture, clear: Bool) -> MTLRenderPassDescriptor {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = clear ? .clear : .load
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            return pass
        }

        private static func viewport(_ screen: SZScreen) -> MTLViewport {
            MTLViewport(originX: screen.viewportX, originY: screen.viewportY, width: screen.viewportWidth, height: screen.viewportHeight, znear: 0, zfar: 1)
        }

        private func uploadPalette(_ palette: SZPalette) {
            guard palette.version != paletteVersion else { return }
            paletteVersion = palette.version
            let colors = paletteBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 256)
            for i in 0 ..< 256 {
                let c = i < palette.count ? palette.colors[i] : SZRGBA(0, 0, 0)
                colors[i] = SIMD4(Float(c.r), Float(c.g), Float(c.b), Float(c.a)) / 255
            }
        }

        private func indexTexture(for surface: SZSurface, upload: Bool) -> MTLTexture {
            let width = surface.width, height = surface.height
            var upload = upload
            if indexTextures.first.map({ $0.width != width || $0.height != height }) ?? true {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Uint, width: width, height: height, mipmapped: false)
                descriptor.usage = .shaderRead
                #if targetEnvironment(macCatalyst)
                    descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
                #else
                    descriptor.storageMode = .shared
                #endif
                indexTextures = (0 ..< 3).compactMap { _ in device.makeTexture(descriptor: descriptor) }
                upload = true
            }
            // An unchanged surface (afterglow frames) reuses the last upload.
            guard upload else { return indexTextures[indexSlot] }
            indexSlot = (indexSlot + 1) % indexTextures.count
            let texture = indexTextures[indexSlot]
            surface.pixels.withUnsafeBytes { bytes in
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width)
            }
            return texture
        }

        private func prepareCRTTargets(width: Int, height: Int, levels: Int) {
            func target(_ w: Int, _ h: Int) -> MTLTexture? {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: max(w, 1), height: max(h, 1), mipmapped: false)
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = .private
                return device.makeTexture(descriptor: descriptor)
            }
            if lights.first.map({ $0.width != width || $0.height != height }) ?? true {
                lights = [target(width, height), target(width, height)].compactMap(\.self)
                lightNeedsClear = true
                bloom = []
            }
            if bloom.count != levels {
                bloom = (1 ... levels).compactMap { target(width >> $0, height >> $0) }
            }
        }

        // MARK: - Shaders

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        // One triangle covering the viewport; uv is (0, 0) at the top left.
        vertex VertexOut sz_vertex(uint vid [[vertex_id]]) {
            float2 p = float2((vid << 1) & 2, vid & 2);
            VertexOut out;
            out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
            out.uv = float2(p.x, 1.0 - p.y);
            return out;
        }

        constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);

        static float3 to_linear(float3 c) {
            return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
        }

        static float3 to_srgb(float3 c) {
            c = clamp(c, 0.0, 1.0);
            return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
        }

        struct PlainUniforms {
            float2 size;
            float scale;
            float padding;
        };

        // Sharp bilinear: blend only within the device pixel that crosses a
        // virtual pixel edge.
        fragment float4 sz_plain(
            VertexOut in [[stage_in]],
            texture2d<uint, access::read> indices [[texture(0)]],
            constant float4 *palette [[buffer(0)]],
            constant PlainUniforms &u [[buffer(1)]]
        ) {
            float2 v = in.uv * u.size - 0.5;
            float2 base = floor(v);
            float2 t = clamp((v - base - 0.5) * u.scale + 0.5, 0.0, 1.0);
            int2 last = int2(u.size) - 1;
            int2 c0 = clamp(int2(base), int2(0), last);
            int2 c1 = clamp(int2(base) + 1, int2(0), last);
            float4 a = palette[indices.read(uint2(c0.x, c0.y)).r];
            float4 b = palette[indices.read(uint2(c1.x, c0.y)).r];
            float4 c = palette[indices.read(uint2(c0.x, c1.y)).r];
            float4 d = palette[indices.read(uint2(c1.x, c1.y)).r];
            return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
        }

        struct PhosphorUniforms {
            float4 decay;
        };

        // Each phosphor shows the new frame or its own fading glow,
        // whichever is brighter.
        fragment float4 sz_phosphor(
            VertexOut in [[stage_in]],
            texture2d<uint, access::read> indices [[texture(0)]],
            texture2d<float, access::read> previous [[texture(1)]],
            constant float4 *palette [[buffer(0)]],
            constant PhosphorUniforms &u [[buffer(1)]]
        ) {
            uint2 p = uint2(in.position.xy);
            float3 color = to_linear(palette[indices.read(p).r].rgb);
            float3 glow = u.decay.w > 0.5 ? previous.read(p).rgb * u.decay.rgb : float3(0.0);
            return float4(max(color, glow), 1.0);
        }

        // Half-size, with a 5-tap kernel: the center and four diagonals.
        fragment float4 sz_down(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
            float2 texel = 1.0 / float2(source.get_width(), source.get_height());
            float2 uv = in.uv;
            float3 c = source.sample(linearClamp, uv).rgb * 4.0;
            c += source.sample(linearClamp, uv + texel * float2(-1, -1)).rgb;
            c += source.sample(linearClamp, uv + texel * float2(1, -1)).rgb;
            c += source.sample(linearClamp, uv + texel * float2(-1, 1)).rgb;
            c += source.sample(linearClamp, uv + texel * float2(1, 1)).rgb;
            return float4(c / 8.0, 1.0);
        }

        // Up one level with an 8-tap tent, added onto what is there.
        fragment float4 sz_up(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
            float2 texel = 1.0 / float2(source.get_width(), source.get_height());
            float2 uv = in.uv;
            float3 c = 0.0;
            c += source.sample(linearClamp, uv + texel * float2(-1, 0)).rgb * 2.0;
            c += source.sample(linearClamp, uv + texel * float2(1, 0)).rgb * 2.0;
            c += source.sample(linearClamp, uv + texel * float2(0, -1)).rgb * 2.0;
            c += source.sample(linearClamp, uv + texel * float2(0, 1)).rgb * 2.0;
            c += source.sample(linearClamp, uv + texel * float2(-1, -1)).rgb;
            c += source.sample(linearClamp, uv + texel * float2(1, -1)).rgb;
            c += source.sample(linearClamp, uv + texel * float2(-1, 1)).rgb;
            c += source.sample(linearClamp, uv + texel * float2(1, 1)).rgb;
            return float4(c / 12.0, 1.0);
        }

        struct CRTUniforms {
            float2 size;
            float scale;
            float scanlines;
            float beamDim;
            float beamBright;
            float maskStrength;
            int maskType;
            float halation;
            float vignette;
            float brightness;
            float ambient;
            float bloomLevels;
            float padding;
        };

        // One virtual row, sharp horizontally.
        static float3 row_light(texture2d<float, access::read> light, float x, int row, float2 size, float scale) {
            int y = clamp(row, 0, int(size.y) - 1);
            float v = x - 0.5;
            float base = floor(v);
            float t = clamp((v - base - 0.5) * scale + 0.5, 0.0, 1.0);
            int x0 = clamp(int(base), 0, int(size.x) - 1);
            int x1 = clamp(int(base) + 1, 0, int(size.x) - 1);
            return mix(light.read(uint2(x0, y)).rgb, light.read(uint2(x1, y)).rgb, t);
        }

        fragment float4 sz_present(
            VertexOut in [[stage_in]],
            texture2d<float, access::read> light [[texture(0)]],
            texture2d<float> bloom [[texture(1)]],
            constant CRTUniforms &u [[buffer(0)]]
        ) {
            float2 v = in.uv * u.size;
            float3 flat = row_light(light, v.x, int(floor(v.y)), u.size, u.scale);

            // Gaussian beams from the rows around this one; bright rows swell.
            float3 beam = 0.0;
            int row = int(floor(v.y));
            for (int k = -2; k <= 2; k++) {
                int r = row + k;
                float3 c = row_light(light, v.x, r, u.size, u.scale);
                float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
                float sigma = mix(u.beamDim, u.beamBright, clamp(lum, 0.0, 1.0));
                sigma = sqrt(sigma * sigma + 1.0 / (12.0 * u.scale * u.scale));
                float d = v.y - (float(r) + 0.5);
                float w = exp(-d * d / (2.0 * sigma * sigma)) / (sigma * 2.5066283);
                beam += c * w;
            }
            // Too few device pixels per row to show lines: fade them out.
            float lines = u.scanlines * clamp((u.scale - 1.5) / 1.0, 0.0, 1.0);
            float3 color = mix(flat, beam, lines);

            // Shadow mask, compensated so it dims nothing on average.
            if (u.maskType != 0 && u.maskStrength > 0.0) {
                uint2 d = uint2(in.position.xy);
                uint channel = d.x % 3;
                float low = 1.0 - u.maskStrength;
                float3 mask = float3(low);
                if (u.maskType == 3) channel = (d.x + (d.y % 2) * 2) % 3;
                mask[channel] = 1.0;
                if (u.maskType == 2 && ((d.y + ((d.x / 3) % 2) * 2) % 4) == 0) mask *= low;
                color *= mask * (3.0 / (1.0 + 2.0 * low));
            }

            // Halation: the blurred light, without lines or mask.
            float3 halo = bloom.sample(linearClamp, in.uv).rgb / u.bloomLevels;
            color += halo * u.halation;

            float2 q = in.uv * 2.0 - 1.0;
            color *= 1.0 - u.vignette * 0.5 * dot(q, q);
            color = color * u.brightness + u.ambient * float3(0.35, 0.5, 0.7);
            return float4(to_srgb(color), 1.0);
        }
        """
    }
#endif
