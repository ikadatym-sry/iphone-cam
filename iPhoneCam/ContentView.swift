import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var server = StreamServer()
    @State private var wifiIP: String = "Detecting Wi-Fi..."
    @State private var showControls: Bool = true
    @State private var isCopied: Bool = false
    
    var body: some View {
        ZStack {
            // Fullscreen Camera Preview
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showControls.toggle()
                    }
                }
            
            // On-Screen HUD Overlay
            if showControls {
                VStack {
                    topBar
                    Spacer()
                    bottomControlBar
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .transition(.opacity)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            refreshNetwork()
            
            // Connect camera frame stream directly to HTTP server
            camera.onFrameCaptured = { [weak server] data in
                server?.sendFrame(data)
            }
            
            camera.start()
            server.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            camera.stop()
            server.stop()
        }
    }
    
    // MARK: - Top Information Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            // Live Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(server.connectedClientsCount > 0 ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                
                Text(server.connectedClientsCount > 0 ? "LIVE (\(server.connectedClientsCount) OBS)" : "STANDBY")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            .cornerRadius(20)
            
            // OBS Streaming URL
            Button(action: copyURL) {
                HStack(spacing: 6) {
                    Image(systemName: isCopied ? "checkmark" : "link")
                        .font(.system(size: 12, weight: .semibold))
                    Text(currentURL)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    if isCopied {
                        Text("COPIED!")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
            }
            
            Spacer()
            
            // FPS & Active Resolution Badge
            HStack(spacing: 8) {
                Text("\(camera.currentFPS) FPS")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                
                Text(camera.activePresetName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.yellow)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            .cornerRadius(20)
        }
    }
    
    // MARK: - Bottom Controls Bar
    private var bottomControlBar: some View {
        HStack(spacing: 16) {
            // Switch Front / Back Camera
            Button(action: {
                camera.switchCamera()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.rotate.fill")
                    Text(camera.currentPosition == .back ? "Back Cam" : "Front Cam")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.85))
                .cornerRadius(12)
            }
            
            // Resolution Picker
            HStack(spacing: 4) {
                ForEach(CameraResolution.allCases) { res in
                    Button(action: {
                        camera.setResolution(res)
                    }) {
                        Text(res.rawValue.components(separatedBy: " ").first ?? "")
                            .font(.system(size: 12, weight: camera.selectedResolution == res ? .bold : .regular))
                            .foregroundColor(camera.selectedResolution == res ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(camera.selectedResolution == res ? Color.white : Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
            
            // Compression Quality Menu
            Menu {
                Button("Maximum Clarity (95%)") { camera.compressionQuality = 0.95 }
                Button("High Quality (85% - Recommended)") { camera.compressionQuality = 0.85 }
                Button("Smooth / Low Wi-Fi (70%)") { camera.compressionQuality = 0.70 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Quality")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
            }
            
            Spacer()
            
            // Refresh IP Button
            Button(action: refreshNetwork) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
            }
            
            // Hide Controls Button
            Button(action: {
                withAnimation { showControls = false }
            }) {
                Image(systemName: "eye.slash.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Helpers
    private var currentURL: String {
        "http://\(wifiIP):\(server.port)"
    }
    
    private func refreshNetwork() {
        if let ip = NetworkUtils.getWiFiAddress() {
            wifiIP = ip
        } else {
            wifiIP = "No Wi-Fi"
        }
    }
    
    private func copyURL() {
        UIPasteboard.general.string = currentURL
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isCopied = false
        }
    }
}

// MARK: - UIKit Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let connection = uiView.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

