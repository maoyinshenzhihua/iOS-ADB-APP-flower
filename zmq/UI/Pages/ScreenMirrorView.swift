import SwiftUI

struct ScreenMirrorView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var isMirroring = false
    @State private var renderer = ScreenRenderer(frame: .zero, device: MTLCreateSystemDefaultDevice())
    @State private var decoder = H264Decoder()
    @State private var scrcpyServer: ScrcpyServer?
    @State private var touchMapper = TouchMapper()

    var body: some View {
        NavigationView {
            VStack {
                if isMirroring {
                    ScreenRenderRepresentable(renderer: renderer)
                        .aspectRatio(CGFloat(touchMapper.deviceWidth) / CGFloat(max(touchMapper.deviceHeight, 1)), contentMode: .fit)
                        .overlay(
                            TouchOverlay(touchMapper: touchMapper) { point in
                                handleTouch(at: point)
                            }
                        )
                        .background(Color.black)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "display")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("点击开始投屏")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
            .navigationTitle("投屏控制")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: { sendKey(.home) }) {
                        Image(systemName: "house")
                    }
                    .disabled(!isMirroring)

                    Button(action: { sendKey(.back) }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!isMirroring)

                    Button(action: { sendKey(.menu) }) {
                        Image(systemName: "line.3.horizontal")
                    }
                    .disabled(!isMirroring)

                    Spacer()

                    Button(isMirroring ? "停止" : "开始") {
                        if isMirroring {
                            stopMirroring()
                        } else {
                            startMirroring()
                        }
                    }
                    .disabled(!adbClient.isConnected)
                }
            }
        }
    }

    private func startMirroring() {
        guard adbClient.isConnected else { return }

        let fileSync = ADBFileSync(client: adbClient)
        let server = ScrcpyServer(client: adbClient, fileSync: fileSync)
        scrcpyServer = server

        decoder.onFrameDecoded = { pixelBuffer in
            renderer.render(pixelBuffer: pixelBuffer)
        }

        server.onDeviceMeta = { meta in
            touchMapper.deviceWidth = meta.width
            touchMapper.deviceHeight = meta.height
        }

        server.onVideoFrame = { frameData in
            decoder.decodeNALUs(from: frameData)
        }

        server.onDisconnected = {
            DispatchQueue.main.async {
                isMirroring = false
            }
        }

        isMirroring = true

        Task {
            _ = await server.start()
        }
    }

    private func stopMirroring() {
        scrcpyServer?.stop()
        scrcpyServer = nil
        isMirroring = false
    }

    private func handleTouch(at point: CGPoint) {
        let mapped = touchMapper.mapTouch(iosPoint: point)
        scrcpyServer?.sendTouchEvent(action: 0, x: Int32(mapped.x), y: Int32(mapped.y))
    }

    private func sendKey(_ keyCode: ADBKeyCode) {
        let shell = ADBShell(client: adbClient)
        Task {
            _ = await shell.executeCommand("input keyevent \(keyCode.rawValue)")
        }
    }
}

struct ScreenRenderRepresentable: UIViewRepresentable {
    let renderer: ScreenRenderer

    func makeUIView(context: Context) -> ScreenRenderer {
        return renderer
    }

    func updateUIView(_ uiView: ScreenRenderer, context: Context) {}
}
