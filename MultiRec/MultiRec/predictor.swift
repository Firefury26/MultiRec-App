import Foundation
import Vision
import CoreMedia
import CoreML
import AVFoundation

protocol PredictorDelegate: AnyObject {
    func predictor(_ predictor: Predictor, didFindNewRecognizedPoints points: [VNHumanBodyPoseObservation.JointName: CGPoint], in boundingBox: CGRect)
    func predictor(_ predictor: Predictor, didLabelAction action: String, with confidence: Double)
}

class Predictor: NSObject {
    weak var delegate: PredictorDelegate?
    let confidenceThreshold: Double = 0.2
    
    let abuseClassifier: Abuse_1
    let arrestClassifier: Arrest_1
    let shopliftingClassifier: Shoplifting_1_copy
    let vandalismClassifier: Vandalism_1
    
    private let captureSession = AVCaptureSession()
    
    override init() {
        do {
            abuseClassifier = try Abuse_1(configuration: MLModelConfiguration())
            arrestClassifier = try Arrest_1(configuration: MLModelConfiguration())
            shopliftingClassifier = try Shoplifting_1_copy(configuration: MLModelConfiguration())
            vandalismClassifier = try Vandalism_1(configuration: MLModelConfiguration())
            
            super.init()
            
            setupCamera()
        } catch {
            fatalError("Failed to initialize classifiers: \(error)")
        }
    }
    
    public func setupCamera() {
        captureSession.beginConfiguration()
        
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            fatalError("Failed to set up video input")
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.commitConfiguration()
    }
    
    func startCapture() {
        captureSession.startRunning()
    }
    
    func stopCapture() {
        captureSession.stopRunning()
    }
    
    func estimation(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer: pixelBuffer)
    }
    
    public func processFrame(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanBodyPoseRequest(completionHandler: bodyPoseHandler)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("Error performing request: \(error)")
        }
    }
    
    public func bodyPoseHandler(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNHumanBodyPoseObservation],
              let firstObservation = observations.first else { return }
        
        guard let recognizedPoints = try? firstObservation.recognizedPoints(.all) else { return }
        let points = recognizedPoints.compactMapValues { $0 }.mapValues { CGPoint(x: $0.x, y: $0.y) }
        
        let boundingBox = calculateBoundingBox(from: points)
        delegate?.predictor(self, didFindNewRecognizedPoints: points, in: boundingBox)
        
        
        if let poseMultiArray = prepareInputWithObservation(firstObservation) {
            
            predictAction(for: poseMultiArray)
        } else {
            print("Failed to prepare input data for predictions")
        }
    }
    
    public func calculateBoundingBox(from points: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> CGRect {
        let minX = points.values.map { $0.x }.min() ?? 0
        let minY = points.values.map { $0.y }.min() ?? 0
        let maxX = points.values.map { $0.x }.max() ?? 0
        let maxY = points.values.map { $0.y }.max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
    
    public func predictAction(for poseMultiArray: MLMultiArray) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("Predicting action for the current frame...")
                
                let abusePrediction = try self.abuseClassifier.prediction(poses: poseMultiArray)
                print("Abuse model prediction made. Confidence: \(abusePrediction.labelProbabilities["abnormal"] ?? 0.0)")
                
                let arrestPrediction = try self.arrestClassifier.prediction(poses: poseMultiArray)
                print("Arrest model prediction made. Confidence: \(arrestPrediction.labelProbabilities["abnormal"] ?? 0.0)")
                
                let shopliftingPrediction = try self.shopliftingClassifier.prediction(poses: poseMultiArray)
                print("Shoplifting model prediction made. Confidence: \(shopliftingPrediction.labelProbabilities["abnormal"] ?? 0.0)")
                
                let vandalismPrediction = try self.vandalismClassifier.prediction(poses: poseMultiArray)
                print("Vandalism model prediction made. Confidence: \(vandalismPrediction.labelProbabilities["abnormal"] ?? 0.0)")
                
                var detectedAction: String?
                var highestConfidence: Double = 0.0
                
                if let abuseLabel = abusePrediction.labelProbabilities["abnormal"], abuseLabel >= self.confidenceThreshold {
                    detectedAction = "Abuse"
                    highestConfidence = abuseLabel
                }
                if let arrestLabel = arrestPrediction.labelProbabilities["abnormal"], arrestLabel >= self.confidenceThreshold {
                    if arrestLabel > highestConfidence {
                        detectedAction = "Arrest"
                        highestConfidence = arrestLabel
                    }
                }
                if let shopliftingLabel = shopliftingPrediction.labelProbabilities["abnormal"], shopliftingLabel >= self.confidenceThreshold {
                    if shopliftingLabel > highestConfidence {
                        detectedAction = "Shoplifting"
                        highestConfidence = shopliftingLabel
                    }
                }
                if let vandalismLabel = vandalismPrediction.labelProbabilities["abnormal"], vandalismLabel >= self.confidenceThreshold {
                    if vandalismLabel > highestConfidence {
                        detectedAction = "Vandalism"
                        highestConfidence = vandalismLabel
                    }
                }
                
                if let action = detectedAction {
                    NotificationCenter.default.post(name: .actionDetectedNotification, object: nil, userInfo: ["actionMessage": "Action Detected: \(action), Confidence: \(highestConfidence)"])
                    
                    print("Detected Action: \(action), Confidence: \(highestConfidence)")
                } else {
                    print("Normal activity")
                }
            } catch {
                print("Error predicting action: \(error)")
            }
        }
    }





    public func prepareInputWithObservation(_ observation: VNHumanBodyPoseObservation) -> MLMultiArray? {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
            print("Failed to get recognized points")
            return nil
        }
        
        guard let multiArray = try? MLMultiArray(shape: [60, 3, 18], dataType: .double) else {
            print("Failed to create multi-array")
            return nil
        }
        
        var jointIndex = 0
        for (_, point) in recognizedPoints {
            multiArray[jointIndex] = NSNumber(value: Double(point.x))
            multiArray[jointIndex + 1] = NSNumber(value: Double(point.y))
            jointIndex += 2
        }
        
        return multiArray
    }
}

extension Predictor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        estimation(sampleBuffer: sampleBuffer)
    }
}
