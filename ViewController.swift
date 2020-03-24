//
//  ViewController.swift
//  SpeedWatch
//
//  Created by Leon Sick on 04.03.20.
//  Copyright © 2020 Leon Sick. All rights reserved.
//

import UIKit
import AVKit
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let detectionOverlay = CALayer()
    
    let identifierLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // here is where we start up the camera
        // for more details visit: https://www.letsbuildthatapp.com/course_video?id=1252
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .vga640x480
        
        let curDeviceOrientation = UIDevice.current.orientation
        let videoDeviceOrientation: AVCaptureVideoOrientation?
        let exifOrientation: CGImagePropertyOrientation

        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
            videoDeviceOrientation = .landscapeRight
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on theright
            exifOrientation = .upMirrored
            videoDeviceOrientation = .landscapeLeft
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
            videoDeviceOrientation = .landscapeRight
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
            videoDeviceOrientation = .landscapeLeft
        default:
            exifOrientation = .up
            videoDeviceOrientation = .landscapeLeft
        }

        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        captureSession.addInput(input)
        
        captureSession.startRunning()

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        let previewLayerConnection = previewLayer.connection
        print(previewLayerConnection?.isVideoOrientationSupported)
        if previewLayerConnection!.isVideoOrientationSupported
        {
            previewLayerConnection?.videoOrientation = videoDeviceOrientation!
        }
        else
        {
            print("Cannot rotate video")
        }
        
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        let rootLayer = view.layer
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: self.view.frame.width,
                                         height: self.view.frame.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        captureSession.addOutput(videoDataOutput)
        
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        
        captureSession.commitConfiguration()
        
//        VNImageRequestHandler(cgImage: <#T##CGImage#>, options: [:]).perform(<#T##requests: [VNRequest]##[VNRequest]#>)
        
        setupIdentifierConfidenceLabel()
    }
    
//    override var shouldAutorotate: Bool
//    {
//        return true
//    }
    
//    override var supportedInterfaceOrientations:UIInterfaceOrientationMask
//    {
//        return UIInterfaceOrientationMask.all
//    }
    
    
    
    fileprivate func setupIdentifierConfidenceLabel() {
        view.addSubview(identifierLabel)
        identifierLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32).isActive = true
        identifierLabel.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        identifierLabel.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        identifierLabel.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        print("Camera was able to capture a frame:", Date())
        
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        guard let model = try? VNCoreMLModel(for: FirstTrafficSignDetector_1178().model) else { return }
        
        let objectRecognition = VNCoreMLRequest(model: model, completionHandler: { (request, error) in
            
//            guard let ergebnis = request.results as? [VNRecognizedObjectObservation] else {return}
            
            DispatchQueue.main.async(execute: {
                // perform all the UI updates on the main queue
                if let results = request.results {
                    self.drawVisionRequestResults(results)
                }
            })
        })
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([objectRecognition])
    }
    
    
    
    

    func drawVisionRequestResults(_ results: [Any])
    {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            let pct = Float(Int(topLabelObservation.confidence * 10000)) / 100
            print(topLabelObservation.identifier.uppercased())
            self.identifierLabel.text = "\(topLabelObservation.identifier.uppercased()), \(pct)%"
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(self.view.frame.width), Int(self.view.frame.height))

            var shapeLayer = CALayer()
            var textLayer = CALayer()

            shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)

//            textLayer = self.createTextSubLayerInBounds(objectBounds,
//                                                            identifier: topLabelObservation.identifier,
//                                                            confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            self.detectionOverlay.addSublayer(shapeLayer)
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
           let textLayer = CATextLayer()
           textLayer.name = "Object Label"
           let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
           let largeFont = UIFont(name: "Helvetica", size: 24.0)!
           formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
           textLayer.string = formattedString
           textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
           textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
           textLayer.shadowOpacity = 0.7
           textLayer.shadowOffset = CGSize(width: 2, height: 2)
           textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
           textLayer.contentsScale = 2.0 // retina rendering
           // rotate the layer into screen orientation and scale and mirror
           textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
           return textLayer
       }
       
       func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
           let shapeLayer = CALayer()
           shapeLayer.bounds = bounds
           shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
           shapeLayer.name = "Found Object"
           shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
           shapeLayer.cornerRadius = 7
           return shapeLayer
       }
        
        func updateLayerGeometry() {
            let bounds = view.layer.bounds
            var scale: CGFloat
            
            let xScale: CGFloat = bounds.size.width / self.view.frame.height
            let yScale: CGFloat = bounds.size.height / self.view.frame.width
            
            scale = fmax(xScale, yScale)
            if scale.isInfinite {
                scale = 1.0
            }
            
            CATransaction.begin()
            CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
            
            // rotate the layer into screen orientation and scale and mirror
            detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
            // center the layer
            detectionOverlay.position = CGPoint (x: bounds.midX, y: bounds.midY)
            
            CATransaction.commit()
            
        }
        
        override var shouldAutorotate: Bool
           {
               return false
           }
    
//        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
//        {
//            //
//            // call super so the coordinator can be passed on
//            // to views and child view controllers.
//            //
//            super.viewWillTransition(to: size, with: coordinator)
//
//            if let videoPreviewLayerConnection = cameraPreviewView.videoPreviewLayer.connection
//            {
//                //
//                // Change the orientation of the video session
//                //
//                let deviceOrientation = UIDevice.current.orientation
//                if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
//                    videoPreviewLayerConnection.videoOrientation = newVideoOrientation
//                }
//            }
//        }
        
        
        
        
        
        
        
//        let request = VNCoreMLRequest(model: model) { (finishedReq, err) in
//
//            //perhaps check the err
//
//            print(finishedReq.results)
//
//            guard let results = finishedReq.results as? [VNClassificationObservation] else { return }
//
//            guard let firstObservation = results.first else { return }
//
//            print(firstObservation.identifier, firstObservation.confidence)
//
//            DispatchQueue.main.async {
//                self.identifierLabel.text = "\(firstObservation.identifier) \(firstObservation.confidence * 100)"
//            }
//
//        }
        
//        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    
    
}

