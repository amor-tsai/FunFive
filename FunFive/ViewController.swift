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
class ViewController: UIViewController, ModelWrapperDelegate, SpeechRecognizerDelegate {
    
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
    private let SERVER_URL = "http://192.168.1.120:8000" // in-house server
//    private let SERVER_URL = "http://10.8.104.90:8000" //
    
    // model id(1 represents LSTM, 2 represents GRU)
    // this value can be changed by segmented control
    private var dsid = 1
    
    // use this to determine how many epochs the model should run
    private var epochs = 1 {
        willSet(newValue) {
            DispatchQueue.main.async {
                self.epochsLable.text = "Current epochs \(newValue)"
            }
        }
    }
    
    // use delegate here so I can pass message from ModelWrapper to this viewController
    private lazy var modelWrapper:ModelWrapper = {
        let model = ModelWrapper(url: SERVER_URL, delegate: self)
        return model
    }()
    
    private lazy var speechRecognizer:SpeechRecognizer = {
        let speechRecognizer = SpeechRecognizer(delegate: self)
        return speechRecognizer
    }()
    
    // MARK: UI LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // set multiline text
        self.dictation.numberOfLines = 5
        
        // max and min value of epochs
        self.epochsAdjustment.maximumValue = 20
        self.epochsAdjustment.minimumValue = 1
        
        //
        self.dictation.layer.masksToBounds = true
        self.dictation.layer.cornerRadius = 20
        
        self.classification.layer.masksToBounds = true
        self.classification.layer.cornerRadius = 20
        
    }

    
    // It's called when there will be a new prediction in ModelWrapper
    // since I implemented the ModelWrapperDelegate protocol
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
    
    // It's called when there is a new spoken text recognized
    func spokenTextReconized(value: String) {
        DispatchQueue.main.async {
            self.dictation.text = value
        }
    }
    
    // It's called when there will be a new accuracy value after the model update
    // since I implemented the ModelWrapperDelegate protocol
    func accuracyWillChange(value: Double) {
        var modelName:String
        if self.dsid == 1 {
            modelName = "LSTM"
        } else {
            modelName = "GRU"
        }
        
        DispatchQueue.main.async {
            self.classification.text = "\(modelName) accuracy: \(String(format: "%.3f", value))"
        }
    }
    
    // MARK: UI Elements
    @IBAction func recordingPressed(_ sender: UIButton) {
        // make the system symbol larger
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 25, weight: .bold, scale: .large)
        // set button to display "recording"
        sender.setImage(UIImage(systemName: "mic.circle.fill", withConfiguration: largeConfig), for: .normal)
        sender.backgroundColor = UIColor.gray
        
        speechRecognizer.startRecording()

    }
    
    
    @IBAction func recordingReleased(_ sender: UIButton) {
        speechRecognizer.stopRecording()
        
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
    @IBOutlet weak var epochsLable: UILabel!
    @IBOutlet weak var epochsAdjustment: UISlider!
    
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
    // 4. other issues when converting RNN Model to CoreML such as BatchNormalization does not support in keras normalization
    // so I just leave the button here, If I can fix those issues then I can open it again.
    
//    @IBAction func switchCoreML(_ sender: Any) {
//        if coreMLSwitch.isOn {
//            coreMLSwitchDesc.text = "CoreML Disable"
//        } else {
//            coreMLSwitchDesc.text = "CoreML Disable"
//        }
//    }
    
    // make model
    // we can choose model by dsid or change the epochs the model shoud run
    @IBAction func sendUpdateModelRequest(_ sender: Any) {
        modelWrapper.makeModel(dsid: self.dsid, epochs: self.epochs)
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
    
    @IBAction func adjustEpochs(_ sender: UISlider) {
        self.epochs = Int(sender.value)
    }
    
    
}

