//
//  ViewController.swift
//  FunFive
//
//  Created by Amor on 2021/11/8.
//

import UIKit
import AVFoundation
import Speech

// starter code from https://github.com/SMU-MSLC/SpeechAndSoundAnalysis
class ViewController: UIViewController, ModelWrapperDelegate {
    
    // MARK: Properties
    // The speech recogniser used by the controller to record the user's speech.
    private let speechRecogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        
    // The current speech recognition request. Created when the user wants to begin speech recognition
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        
    // The current speech recognition task. Created when the user wants to begin speech recognition.
    private var recognitionTask: SFSpeechRecognitionTask?
        
    // The audio engine used to record input from the microphone.
    private let audioEngine = AVAudioEngine()
    
    // server url
    private let SERVER_URL = "http://192.168.1.120:8000"
    
    // model id(1 represents LSTM, 2 represents GRU)
    private var dsid = 1
    
    private lazy var modelWrapper:ModelWrapper = {
        let model = ModelWrapper(url: SERVER_URL, delegate: self)
        return model
    }()
    
    // MARK: UI LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // set multiline text
        self.dictation.numberOfLines = 5
        
        //
        self.coreMLSwitch.isOn = false
    }
    
    // It's called when dsid will change
    func dsidWillChange(value: Any) {
        // do something
        print(value)
    }
    
    // It's called when there will be a prediction
    func predictionWillChange(value: Any) {
        // do something
        if let pred = value as? Int {
            if pred == 1 {
                DispatchQueue.main.async {
                    self.classification.text = "Positive"
                }
            } else {
                DispatchQueue.main.async {
                    self.classification.text = "Negative"
                }
            }
        }
    }
    
    // MARK: SFAudioTranscription
    func startRecording() {
        // setup recongizer
        guard speechRecogniser.isAvailable else {
            // Speech recognition is unavailable, so do not attempt to start.
            return
        }
        
        // make sure we have permission
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            SFSpeechRecognizer.requestAuthorization({ (status) in
                // Handle the user's decision
                print(status)
            })
            return
        }
        
        
        // setup audio
        let audioSession = AVAudioSession.sharedInstance()
        do{
            try audioSession.setCategory(AVAudioSession.Category.record)
            try audioSession.setMode(AVAudioSession.Mode.measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
        catch {
            fatalError("Audio engine could not be setup")
            
        }

        if recognitionRequest == nil {
            // setup reusable request (if not already)
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            
            // perform on device, if possible
            // NOTE: this will usually limit the voice analytics results
            if speechRecogniser.supportsOnDeviceRecognition {
                print("Using on device recognition, voice analytics may be limited.")
                recognitionRequest?.requiresOnDeviceRecognition = true
            }else{
                print("Using server for recognition.")
            }
        }
        

        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else {
            // Handle error
            return
        }
        
        recognitionTask = speechRecogniser.recognitionTask(with: recognitionRequest) { [unowned self] result, error in
            if let result = result {
                let spokenText = result.bestTranscription.formattedString
                DispatchQueue.main.async{
                    // fill in the label here
                    self.dictation.text = spokenText
                }
            }
            
            if result?.isFinal ?? (error != nil) {
                // this will remove the listening tap
                // so that the transcription stops
                inputNode.removeTap(onBus: 0)
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do{
            try audioEngine.start()
        }
        catch {
            fatalError("Audio engine could not start")
        }
    }
    
    func stopRecording() {
        if audioEngine.isRunning{
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }
    }

    // MARK: UI Elements
    @IBAction func recordingPressed(_ sender: UIButton) {
        // make the system symbol larger
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 25, weight: .bold, scale: .large)
        // set button to display "recording"
        sender.setImage(UIImage(systemName: "mic.circle.fill", withConfiguration: largeConfig), for: .normal)
        sender.backgroundColor = UIColor.gray
        
        self.startRecording()

    }
    
    
    @IBAction func recordingReleased(_ sender: UIButton) {
        self.stopRecording()
        
        // make system symbol larger
        // https://stackoverflow.com/questions/60641048/change-a-sf-symbol-size-inside-a-uibutton
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 25, weight: .bold, scale: .large)
        // set button to display "normal"
        sender.setImage(UIImage(systemName: "mic.circle", withConfiguration: largeConfig), for: .normal)
        sender.backgroundColor = UIColor.white
        
        // call this after recording finished because I'll send the text recoginized to the model
        self.recordingReleasedEvent()
    }
    
    // call this after the recording is completed
    func recordingReleasedEvent() {
        // get text from speech recognition
        if let recordingContent = self.dictation.text {
            if self.trainSwitch.isOn {
                // It's in model training mode so it'll send data to the server
                var label:Int
                if self.labelSwitch.isOn {
                    label = 1
                } else {
                    label = 0
                }
                modelWrapper.sendDataWithString(recordingContent, withLabel: label, dsid: self.dsid)
                
            } else {
                // It's in model prediction mode so it'll get prediction
                modelWrapper.getPrediction(recordingContent,dsid: self.dsid)
                
            }
        }
        
    }
    
    // text converted from voice will appear here
    @IBOutlet weak var dictation: UILabel!
    
    @IBOutlet weak var classification: UILabel!
    @IBOutlet weak var trainSwitchDesc: UILabel!
    @IBOutlet weak var trainSwitch: UISwitch!
    @IBOutlet weak var labelSwitch: UISwitch!
    @IBOutlet weak var labelSwitchDesc: UILabel!
    @IBOutlet weak var coreMLSwitch: UISwitch!
    @IBOutlet weak var coreMLSwitchDesc: UILabel!
    
    
    // use this to change the mode between training and making prediction
    @IBAction func switchMode(_ sender: Any) {
        if trainSwitch.isOn {
            trainSwitchDesc.text = "Train mode ON"
        } else {
            trainSwitchDesc.text = "Train mode OFF"
        }
    }
    
    // use this to change the lable between positive and negative
    @IBAction func switchLable(_ sender: Any) {
        if labelSwitch.isOn {
            labelSwitchDesc.text = "Positive"
        } else {
            labelSwitchDesc.text = "Negative"
        }
    }
    
    // use this to change the model between remote model and coreML
    // I tried to use coreML here, but I have some issues.
    // 1. my env uses tensorflow 2.6, but coreML convertion tool doesn't support tensorflow 2.6
    // 2. A vectorization from a string is needed, but I need time to figure out how to do in swift. I can ask for server to do it for me, either.
    // 3. some libraries can't complie if I try to install tensorflow 2.5, that means I need time to fix the compatibility problem.
    // 4. other issues when converting RNN Model to CoreML
    // so I just leave the button here, If I can fix those issues then I can open it again.
    @IBAction func switchCoreML(_ sender: Any) {
        if coreMLSwitch.isOn {
            coreMLSwitchDesc.text = "CoreML Disable"
        } else {
            coreMLSwitchDesc.text = "CoreML Disable"
        }
    }
    
    // make model
    @IBAction func sendUpdateModelRequest(_ sender: Any) {
        modelWrapper.makeModel(dsid: self.dsid)
    }
    
    // use segmented control to switch different model
    // it can also switch to different prediction based on other values from switchs
    @IBAction func modelSelectChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex{
        case 0:
            self.dsid  = 1
        case 1:
            self.dsid = 2
            
        default:
            return
        }
        
        // if train mode is off, then try to get a prediction.
        if let recognitionContent = self.dictation.text {
            if self.trainSwitch.isOn == false {
                modelWrapper.getPrediction(recognitionContent, dsid: self.dsid)
            }
        }
    }
    
}

