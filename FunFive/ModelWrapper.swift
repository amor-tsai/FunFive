//
//  ModelWrapper.swift
//  FunFive
//
//  wake me up - Avicii
//
//  Created by Amor on 2021/11/14.
//

import Foundation

// I set this protocol because I want to pass values to the viewController
protocol ModelWrapperDelegate: AnyObject{
    func predictionWillChange(value:Any)
    func accuracyWillChange(value:Double)
}

class ModelWrapper: NSObject{
    
    weak var delegate: ModelWrapperDelegate?
    
    // Model Server address
    private var serverURL = ""
    // this key is for authentication, it will be stored in the cookie
    private let passKey = "h7hdg43scbmdTRY7hbv321szxcdOPd2mz1"
    
    private var session: URLSession = {
        let sessionConfig = URLSessionConfiguration.ephemeral
        
        sessionConfig.timeoutIntervalForRequest = 20.0
        sessionConfig.timeoutIntervalForResource = 10.0
        sessionConfig.httpMaximumConnectionsPerHost = 1
        
        return URLSession(configuration: sessionConfig)
    }()
    
    // get the prediction result
    private var prediction: Int = -1 {
        willSet(newValue){
            // It's to delegate to viewController so that it can receive the event of value changed in order to update UI
            delegate?.predictionWillChange(value: newValue)
        }
    }
    
    // the accuracy of the model
    private var accuracy: Double = 0.0 {
        willSet(newValue){
            // It's to delegate to any implemented ModelWrapperDelegate so that it can receive the event of value changed in order to update UI
            delegate?.accuracyWillChange(value: newValue)
        }
    }
    
    init(url:String, delegate:ModelWrapperDelegate) {
        self.serverURL = url
        self.delegate = delegate
    }

    // feed data into the model
    func sendDataWithString(_ content:String, withLabel label:Int, dsid:Int) {
        let baseURL = "\(serverURL)/AddDataPoint"
        let postURL = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postURL!)
        
        // data to send in body of post request (send arguments as json)
        let jsonUpload:NSDictionary = ["feature":content,
                                       "label":"\(label)",
                                       "dsid":dsid]
        
        
        let requestBody:Data? = self.convertDictionaryToData(with:jsonUpload)
        
        request.httpMethod = "POST"
        request.httpBody = requestBody
        
        // set cookies for authentication
        request.setValue("pass=\(passKey)", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = true
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
            completionHandler:{(data, response, error) in
                if(error != nil){
                    if let res = response{
                        print("Response:\n",res)
                    }
                }
                else{
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    
                    print(jsonDictionary["feature"]!)
                    print(jsonDictionary["label"]!)
                }

        })
        
        postTask.resume() // start the task
    }
    
    func getPrediction(_ recordingContent:String, dsid:Int){
        let baseURL = "\(serverURL)/PredictOne"
        let postURL = URL(string: "\(baseURL)")
        
        // create a custom HTTP POST request
        var request = URLRequest(url: postURL!)
        
        // data to send in body of post request (send arguments as json)
        let jsonUpload:NSDictionary = ["feature":recordingContent, "dsid":dsid]
        
        
        let requestBody:Data? = self.convertDictionaryToData(with:jsonUpload)
        
        request.httpMethod = "POST"
        request.httpBody = requestBody
        
        // set cookies for authentication
        request.setValue("pass=\(passKey)", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = true
        
        let postTask : URLSessionDataTask = self.session.dataTask(with: request,
                                                                  completionHandler:{
                        (data, response, error) in
                        if(error != nil){
                            if let res = response{
                                print("Response:\n",res)
                            }
                        }
                        else{ // no error we are aware of
                            
                            let jsonDictionary = self.convertDataToDictionary(with: data)
                            print("jsonDic: \(jsonDictionary)")
                            let labelResponse:String = jsonDictionary["prediction"]! as! String
                            self.prediction = Int(labelResponse)!
                        }
                                                                    
        })
        
        postTask.resume() // start the task
    }
    
    func makeModel(dsid:Int,epochs:Int) {
        
        // create a GET request for server to update the ML model with current data
        let baseURL = "\(serverURL)/UpdateModel"
        let query = "?dsid=\(dsid)&epochs=\(epochs)"
    
        let getUrl = URL(string: baseURL+query)
        var request: URLRequest = URLRequest(url: getUrl!)
        
        // set cookies
        request.setValue("pass=\(passKey)", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = true
        
        let dataTask : URLSessionDataTask = self.session.dataTask(with: request,
              completionHandler:{(data, response, error) in
                // handle error!
                if (error != nil) {
                    if let res = response{
                        print("Response:\n",res)
                    }
                }
                else{
                    let jsonDictionary = self.convertDataToDictionary(with: data)
                    
                    if let resubAcc = jsonDictionary["resubAccuracy"]{
                        self.accuracy = resubAcc as! Double
                        print("Resubstitution Accuracy is", resubAcc)
                    }
                }
                                                                    
        })
        
        dataTask.resume() // start the task
        
    }
    
    //MARK: JSON Conversion Functions
    func convertDictionaryToData(with jsonUpload:NSDictionary) -> Data?{
        do { // try to make JSON and deal with errors using do/catch block
            let requestBody = try JSONSerialization.data(withJSONObject: jsonUpload, options:JSONSerialization.WritingOptions.prettyPrinted)
            return requestBody
        } catch {
            print("json error: \(error.localizedDescription)")
            return nil
        }
    }
    
    func convertDataToDictionary(with data:Data?)->NSDictionary{
        do { // try to parse JSON and deal with errors using do/catch block
            let jsonDictionary: NSDictionary =
                try JSONSerialization.jsonObject(with: data!,
                                              options: JSONSerialization.ReadingOptions.mutableContainers) as! NSDictionary
            
            return jsonDictionary
            
        } catch {
            
            if let strData = String(data:data!, encoding:String.Encoding(rawValue: String.Encoding.utf8.rawValue)){
                            print("printing JSON received as string: "+strData)
            }else{
                print("json error: \(error.localizedDescription)")
            }
            return NSDictionary() // just return empty
        }
    }
    
}

