import Foundation
import AVFoundation
import CoreImage
import UIKit

enum CameraResolution: String, CaseIterable, Identifiable {
    case res4K = "4K UHD"
    case res1080p = "1080p FHD"
    case res720p = "720p HD"
    
    var id: String { rawValue }
    
    var preset: AVCaptureSession.Preset {
        switch self {
        case .res4K:
            return .hd4K3840x2160
        case .res1080p:
            return .hd1920x1080
        case .res720p:
            return .hd1280x720
        }
    }
}

enum CameraPosition {
    case back
    case front
}

final class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var currentPosition: CameraPosition = .back
    @Published var selectedResolution: CameraResolution = .res1080p
    @Published var currentFPS: Int = 0
    @Published var compressionQuality: Float = 0.85
    @Published var activePresetName: String = "1080p"
    
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.hobby.iphonecam.sessionQueue")
    private let videoOutputQueue = DispatchQueue(label: "com.hobby.iphonecam.videoOutputQueue", qos: .userInteractive)
    
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // FPS tracking
    private var frameCount = 0
    private var lastFpsUpdateTime = Date()
    
    var onFrameCaptured: ((Data) -> Void)?
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            
            // Default to back camera
            self.configureInput(for: .back)
            self.configureOutput()
            self.applyPreset(self.selectedResolution)
            
            self.session.commitConfiguration()
        }
    }
    
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
            }
        }
    }
    
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
    
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            
            let newPosition: CameraPosition = (self.currentPosition == .back) ? .front : .back
            self.configureInput(for: newPosition)
            
            // Re-apply preset (front camera might not support 4K)
            self.applyPreset(self.selectedResolution)
            self.updateVideoOrientation()
            
            self.session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.currentPosition = newPosition
            }
        }
    }
    
    func setResolution(_ resolution: CameraResolution) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.selectedResolution = resolution
            self.applyPreset(resolution)
            self.session.commitConfiguration()
        }
    }
    
    private func configureInput(for position: CameraPosition) {
        if let currentInput = videoInput {
            session.removeInput(currentInput)
        }
        
        let avPosition: AVCaptureDevice.Position = (position == .back) ? .back : .front
        
        let deviceDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: avPosition
        )
        
        guard let device = deviceDiscovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("Failed to get camera input for \(position)")
            return
        }
        
        session.addInput(input)
        self.videoInput = input
        
        // Optimize frame rate to 30 or 60 FPS if supported
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
    }
    
    private func configureOutput() {
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            session.addOutput(videoOutput)
            updateVideoOrientation()
        }
    }
    
    private func applyPreset(_ resolution: CameraResolution) {
        var presetToUse = resolution.preset
        
        // If 4K is selected but current device/session doesn't support it, fallback to 1080p
        if !session.canSetSessionPreset(presetToUse) {
            if session.canSetSessionPreset(.hd1920x1080) {
                presetToUse = .hd1920x1080
            } else if session.canSetSessionPreset(.hd1280x720) {
                presetToUse = .hd1280x720
            } else {
                presetToUse = .high
            }
        }
        
        session.sessionPreset = presetToUse
        
        var displayName = "1080p"
        if presetToUse == .hd4K3840x2160 {
            displayName = "4K UHD"
        } else if presetToUse == .hd1920x1080 {
            displayName = "1080p FHD"
        } else if presetToUse == .hd1280x720 {
            displayName = "720p HD"
        } else {
            displayName = "High"
        }
        
        DispatchQueue.main.async {
            self.activePresetName = displayName
        }
    }
    
    func updateVideoOrientation(orientation: AVCaptureVideoOrientation = .landscapeRight) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
        if connection.isVideoMirroringSupported {
            // Un-mirror front camera so text isn't flipped in OBS
            connection.isVideoMirrored = false
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let quality = CGFloat(compressionQuality)
        
        // Direct hardware-accelerated JPEG encoding
        guard let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        ) else { return }
        
        // Track FPS
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastFpsUpdateTime) >= 1.0 {
            let fps = frameCount
            frameCount = 0
            lastFpsUpdateTime = now
            DispatchQueue.main.async {
                self.currentFPS = fps
            }
        }
        
        onFrameCaptured?(jpegData)
    }
}
