import SwiftUI

struct SecondPage: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var frameHandler = FrameHandler()
    @State public var actionMessage: String = "" // State variable to hold the action message
    
    var body: some View {
        VStack {
            Text("Live Camera Feed")
                .font(.title)
                .padding(.bottom, 30)
            
            if let cgImage = frameHandler.frame {
                CameraPreviewView(cgImage: cgImage)
                    .frame(width: 300, height: 200)
                    .cornerRadius(10)
            } else {
                Text("Camera Feed Placeholder")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            
            // Display the action message
            Text(actionMessage)
                .foregroundColor(.white)
                .padding()
            
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Back")
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .actionDetectedNotification)) { notification in
            if let actionMessage = notification.userInfo?["actionMessage"] as? String {
                print("Received notification: \(actionMessage)") // Print the received message for debugging
                DispatchQueue.main.async {
                    self.actionMessage = actionMessage
                }
            }
        }
    }
}

struct CameraPreviewView: View {
    let cgImage: CGImage
    
    var body: some View {
        Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}

extension Notification.Name {
    static let actionDetectedNotification = Notification.Name("actionDetectedNotification")
}
