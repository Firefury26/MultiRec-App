import SwiftUI
import AVFoundation
import Vision

class ContentView: NSObject, ObservableObject {
    
    var arrestClassifier: VNCoreMLModel?
    var vandalismClassifier: VNCoreMLModel?
    var abuseClassifier: VNCoreMLModel?
    var shopliftingClassifier: VNCoreMLModel?
    
    @Published var classLabel: String = ""
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override init() {
        super.init()
        do {
            arrestClassifier = try? VNCoreMLModel(for: Arrest_1(configuration: MLModelConfiguration()).model)
            vandalismClassifier = try? VNCoreMLModel(for: Vandalism_1(configuration: MLModelConfiguration()).model)
            abuseClassifier = try? VNCoreMLModel(for: Abuse_1(configuration: MLModelConfiguration()).model)
            shopliftingClassifier = try? VNCoreMLModel(for: Shoplifting_1_copy(configuration: MLModelConfiguration()).model)


        } catch {
            print(error)
        }
    }
    
    func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        let videoOutputQueue = DispatchQueue(label: "VideoOutputQueue")
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
    }
    
    func startSession() {
        captureSession.startRunning()
    }
    
    func stopSession() {
        captureSession.stopRunning()
    }
}

extension ContentView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Perform inference using the arrest model
        if let arrestResult = try? performInference(pixelBuffer: pixelBuffer, model: arrestClassifier) {
            if arrestResult.confidence > 0.5 {
                classLabel = "Arrest"
                return
            }
        }
        
        // Perform inference using the vandalism model
        if let vandalismResult = try? performInference(pixelBuffer: pixelBuffer, model: vandalismClassifier) {
            if vandalismResult.confidence > 0.5 {
                classLabel = "Vandalism"
                return
            }
        }
        
        // Perform inference using the abuse model
        if let abuseResult = try? performInference(pixelBuffer: pixelBuffer, model: abuseClassifier) {
            if abuseResult.confidence > 0.5 {
                classLabel = "Abuse"
                return
            }
        }
        
        // Perform inference using the shoplifting model
        if let shopliftingResult = try? performInference(pixelBuffer: pixelBuffer, model: shopliftingClassifier) {
            if shopliftingResult.confidence > 0.5 {
                classLabel = "Shoplifting"
                return
            }
        }
    }
    
    func performInference(pixelBuffer: CVPixelBuffer, model: VNCoreMLModel?) throws -> VNClassificationObservation {
        guard let model = model else {
            throw NSError(domain: "ModelError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model not initialized"])
        }
        
        var classification: VNClassificationObservation?
        
        let request = VNCoreMLRequest(model: model) { (request, error) in
            guard let results = request.results as? [VNClassificationObservation],
                  let firstResult = results.first else {
                return
            }
            classification = firstResult
        }
        
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
        
        guard let result = classification else {
            throw NSError(domain: "ModelError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Inference failed"])
        }
        
        return result
    }
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
}
