import AVFoundation
import CoreImage
import CoreMedia
import Vision

class FrameHandler: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, PredictorDelegate {
    @Published var frame: CGImage?
    private var permissionGranted = true
    public let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let context = CIContext()
    private let predictor = Predictor()
    private var recognizedPoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    private var personBoundingBox: CGRect?
    
    @Published var classifiedAction: String = ""
    
    override init() {
        super.init()
        self.checkPermission()
        sessionQueue.async { [unowned self] in
            self.setupCaptureSession()
            self.captureSession.startRunning()
        }
        
        predictor.delegate = self
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.permissionGranted = true
        case .notDetermined:
            self.requestPermission()
        default:
            self.permissionGranted = false
        }
    }

    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
        }
    }
    
    func setupCaptureSession() {
        let videoOutput = AVCaptureVideoDataOutput()
        
        guard permissionGranted else { return }
        guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera,for: .video, position: .back) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        DispatchQueue.main.async { [unowned self] in
            self.frame = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer)
            self.predictor.processFrame(pixelBuffer: pixelBuffer)
        }
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return cgImage
    }
    
    func predictor(_ predictor: Predictor, didFindNewRecognizedPoints points: [VNHumanBodyPoseObservation.JointName : CGPoint], in boundingBox: CGRect) {
        
        self.recognizedPoints = points
        self.personBoundingBox = boundingBox
    }
    
    func predictor(_ predictor: Predictor, didLabelAction action: String, with confidence: Double) {
        
        DispatchQueue.main.async { [weak self] in
            self?.classifiedAction = action
        }
    }
    
    func predictorDidDetectPerson(_ predictor: Predictor) {
        
        print("Person detected")
    }
}
