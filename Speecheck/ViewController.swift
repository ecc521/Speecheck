//
//  ViewController.swift
//  Speecheck
//
//  Created by Tucker Willenborg on 3/31/19.
//  Copyright © 2019 Tucker Willenborg. All rights reserved.
//



//Offline voice recognition can be activated in Settings>General>Keyboard>Enable Dictation
//If offline dictation is available, text like "You can use Dictation for English when not connected
//to the Internet." will appear under the Enable Dictation switch.
import AVFoundation
import Speech
import UIKit
import Foundation



typealias UIButtonTargetClosure = (UIButton) -> ()

class ClosureWrapper: NSObject {
    let closure: UIButtonTargetClosure
    init(_ closure: @escaping UIButtonTargetClosure) {
        self.closure = closure
    }
}

extension UIButton {
    
    private struct AssociatedKeys {
        static var targetClosure = "targetClosure"
    }
    
    private var targetClosure: UIButtonTargetClosure? {
        get {
            guard let closureWrapper = objc_getAssociatedObject(self, &AssociatedKeys.targetClosure) as? ClosureWrapper else { return nil }
            return closureWrapper.closure
        }
        set(newValue) {
            guard let newValue = newValue else { return }
            objc_setAssociatedObject(self, &AssociatedKeys.targetClosure, ClosureWrapper(newValue), objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    func addTargetClosure(closure: @escaping UIButtonTargetClosure) {
        targetClosure = closure
        addTarget(self, action: #selector(UIButton.closureAction), for: .touchUpInside)
    }
    
    @objc func closureAction() {
        guard let targetClosure = targetClosure else { return }
        targetClosure(self)
    }
}





var monitoring = false;
var startTime = Date().timeIntervalSinceReferenceDate; //This will be overwritten anyways


class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en-US"))
        speechRecognizer!.delegate = self as? SFSpeechRecognizerDelegate
        
        
        var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        var recognitionTask: SFSpeechRecognitionTask?
        let audioEngine = AVAudioEngine()
        
        
        let screenWidth = UIScreen.main.bounds.width
        
        
        var textArea: UITextView = UITextView (frame:CGRect(x: 0, y: 150, width: screenWidth, height: 100));
        self.view.addSubview(textArea)
        textArea.text = "Speech information appears here"
        textArea.font = UIFont.systemFont(ofSize: 20)
        textArea.isUserInteractionEnabled = false
        
        let button = UIButton(frame: CGRect(x: 0, y: 100, width: screenWidth, height: 50))
        button.backgroundColor = .lightGray
        button.setTitle("Begin Monitoring", for: .normal)

        
        
        var outputText: UITextView = UITextView (frame:CGRect(x: 0, y: 250, width: screenWidth, height: 250));
        self.view.addSubview(outputText)
        outputText.text = "What you speak will appear here. Words that the computer finds unclear will be highlighted in red (note - do NOT depend on this. It doesn't appear to work great)"
        outputText.font = UIFont.systemFont(ofSize: 14)
        outputText.isUserInteractionEnabled = false
        
        
        
        func buttonAction(sender: UIButton!) {
            print("Button tapped")
            if (monitoring == false) {
                askPermission()
                monitoring = true
                sender.setTitle("Stop Monitoring (Takes a sec)", for: .normal)
            }
            else {
                //Cancel recording
                monitoring = false
                audioEngine.stop()
                recognitionRequest?.endAudio()
                sender.setTitle("Start Monitoring", for: .normal)
            }
        }


        button.addTargetClosure(closure: buttonAction)
        self.view.addSubview(button)
        
        

        func startRecording() {
            
            if recognitionTask != nil {
                recognitionTask?.cancel()
                recognitionTask = nil
            }
            
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSession.Category.record)
                try audioSession.setMode(AVAudioSession.Mode.measurement)
                try audioSession.setActive(true)
            } catch {
                print("audioSession properties weren't set because of an error.")
            }
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            
            let inputNode = audioEngine.inputNode
            
            guard let recognitionRequest = recognitionRequest else {
                fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { (result, error) in
                
                var isFinal = false
                
                if result != nil {
                    
                    //Do something with the current result
                    let currentText =  result!.bestTranscription.formattedString
                    
                    
                    let segments = result!.bestTranscription.segments
                    //Highlight words with a lower confidence.
                    
                    let formattedText = NSMutableAttributedString(string:currentText)
                    
                    formattedText.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor(red:0, green:0, blue:0, alpha:1), range: NSRange(location: 0,length: formattedText.length))

                    let minConfidence: Float = 0.9 //Minumum confidince to show up as normal
                    for segment in segments {
                        let confidence = segment.confidence
                        //Confidence values take a while before they show up
                        
                        if (confidence < minConfidence && confidence != 0) {
                            print(segment)

                            let difference = minConfidence - confidence
                            
                            let redComponent = CGFloat(difference.squareRoot())
                            
                            formattedText.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor(red:redComponent, green:0, blue:0, alpha:1) , range: segment.substringRange)
                        }
                    }
                    
                    outputText.attributedText = formattedText
                    
                    
                    
                    let words = currentText.components(separatedBy: " ")
                    let time = Date().timeIntervalSinceReferenceDate - startTime
                    let wpm = Double(words.count)/time*60
                    
                    let roundedTime = round(time*100)/100
                    let roundedWPM = round(wpm*100)/100
                    textArea.text = "Rate: \(roundedWPM) words per minute\n Words: \(words.count) \n Time: \(roundedTime) seconds "
                    
                    isFinal = (result?.isFinal)!
                    //If monitoring is false, we are not being stopped by iOS, but rather by the program itself (the user stopped it)
                    if (isFinal && monitoring) {
                        permissionError(errorMessage: "Oh no! It looks like iOS has terminated Speecheck's speech recognition.")
                        monitoring = false
                        button.setTitle("Try to Restart Monitoring", for: .normal)
                    }
                }
                
                if error != nil || isFinal {
                    //Recording has stopped, either due to an error, or ending for some reasom
                    audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    recognitionTask = nil
                    
                    if (isFinal == false) {
                        print("An error occoured \(String(describing: error))")
                    }
                    
                    //microphoneButton.isEnabled = true
                }
            })
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
                recognitionRequest.append(buffer)
            }
            
            audioEngine.prepare()
            
            do {
                try audioEngine.start()
            } catch {
                print("audioEngine couldn't start because of an error.")
            }
            
            startTime = Date().timeIntervalSinceReferenceDate
            textArea.text = "Recording has Begun."
            print("Recording now")
        }

        

        func askPermission() {
            SFSpeechRecognizer.requestAuthorization { (authStatus) in
                OperationQueue.main.addOperation {
                    switch authStatus {
                    case .authorized:
                        begin()
                        // Good to go
                        break
                    case .denied:
                        // User said no
                        permissionError(errorMessage: "Speecheck requies speech recognition to work. You may need to go into settings to give permission.")
                        break
                    case .restricted:
                        // Device isn't permitted
                        permissionError(errorMessage: "It appears like iOS is blocking this app from speech recognition")
                        break
                    case .notDetermined:
                        // Don't know yet
                        permissionError(errorMessage: "Something wen't wrong obtaining permission. It appears the request was dismissed, rather than accepted or denied")
                        break
                    @unknown default:
                        permissionError(errorMessage: "Your device did something unexpected. Perhaps your device is newer than this app supports.")
                    }
                }
            }
        }
        
        
        func permissionError(errorMessage: String) {
            let alertController = UIAlertController(title: "Error", message: errorMessage, preferredStyle: UIAlertController.Style.alert)
            alertController.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
        }
        

        
        func begin() {
            print("Starting recognition")
            startRecording()
        }
        
        
    }
    

    
}













