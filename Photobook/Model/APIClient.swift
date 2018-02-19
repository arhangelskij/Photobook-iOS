//
//  APIClient.swift
//  Photobook
//
//  Created by Jaime Landazuri on 16/11/2017.
//  Copyright © 2017 Kite.ly. All rights reserved.
//

import Foundation
import UIKit

enum APIClientError: Error {
    case parsing
    case connection
    case server(code: Int, message: String)
}

enum APIContext {
    case none
    case photobook
    case pig
}

// Image types
enum ImageType: String {
    case jpeg = "jpeg"
    case png = "png"
}

/// Network client for all interaction with the API
class APIClient: NSObject {
    
    // Notification keys
    static let backgroundSessionTaskFinished = Notification.Name("APIClientBackgroundSessionTaskFinished")
    static let backgroundSessionAllTasksFinished = Notification.Name("APIClientBackgroundSessionAllTaskFinished")
    
    // Storage constants
    private struct Storage {
        static let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        static let uploadTasksFile: String = { return documentsDirectory.appending("/Photobook/PBUploadTasks.dat") }()
    }
    
    private struct Constants {
        static let backgroundSessionBaseIdentifier = "ly.kite.photobook.backgroundSession"
        static let errorDomain = "Photobook.APIClient.APIClientError"
    }
    
    // Available methods
    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }
    
    private func baseURLString(for context: APIContext) -> String {
        switch context {
        case .none: return ""
        case .photobook: return "https://photobook-builder.herokuapp.com/"
        case .pig: return "https://piglet.kite.ly/"
        }
    }

    
    /// Shared client
    static let shared: APIClient = {
        let apiClient = APIClient()
        NotificationCenter.default.addObserver(apiClient, selector: #selector(savePendingTasks), name: .UIApplicationWillTerminate, object: nil)
        NotificationCenter.default.addObserver(apiClient, selector: #selector(savePendingTasks), name: .UIApplicationDidEnterBackground, object: nil)
        
        return apiClient
    }()
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Url session for regular tasks
    private let urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: nil, delegateQueue: OperationQueue.main)
    
    // Url session for background upload tasks
    private lazy var backgroundUrlSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Constants.backgroundSessionBaseIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }()
    
    // Completion handler to execute when the app has been woken up by finished tasks
    private var backgroundSessionCompletionHandler: (()->())? = nil
    
    // Dictionary with upload task identifiers keys and semantic references
    private var taskReferences: [Int: String] = {
        if let references = NSKeyedUnarchiver.unarchiveObject(withFile: Storage.uploadTasksFile) as? [Int: String] {
            return references
        }
        return [Int: String]()
    }()
    
    private func createFileWith(imageData:Data, imageName:String, imageType:ImageType, boundaryString:String) -> URL {
        
        let directoryUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileUrl = directoryUrl.appendingPathComponent(NSUUID().uuidString)
        let filePath = fileUrl.path
        
        FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil)
        let fileHandle = FileHandle(forWritingAtPath: filePath)!
        
        var header = ""
        header += "--\(boundaryString)\r\n"
        header += "Content-Disposition: form-data; charset=utf-8; name=\"file\"; filename=\"\(imageName).\(imageType)\"\r\n"
        header += "Content-Type: image/\(imageType)\r\n\r\n"
        let headerData = header.data(using: .utf8, allowLossyConversion: false)!
        
        let footer = "\r\n--\(boundaryString)--\r\n"
        let footerData = footer.data(using: .utf8, allowLossyConversion: false)!
        
        fileHandle.write(headerData)
        fileHandle.write(imageData)
        fileHandle.write(footerData)
        fileHandle.closeFile()
        
        return fileUrl
    }

    private func imageData(withImage image: UIImage, forType imageType: ImageType) -> Data? {
        let imageData:Data
        
        switch imageType {
        case .jpeg:
            guard let data = UIImageJPEGRepresentation(image, 0.8) else {
                return nil
            }
            imageData = data
        case .png:
            guard let data = UIImagePNGRepresentation(image) else {
                return nil
            }
            imageData = data
        }
        
        return imageData
    }
    
    // MARK: Background tasks
    
    /// Called when the app is launched by the system by pending tasks
    ///
    /// - Parameter completionHandler: The completion handler provided by the system and that should be called when the event handling is done.
    func recreateBackgroundSession(_ completionHandler: @escaping ()->Void) {
        self.backgroundSessionCompletionHandler = completionHandler
        
        // Trigger lazy initialisation
        _ = backgroundUrlSession
    }
    
    /// Save semantic references for pending upload tasks to disk
    @objc func savePendingTasks() {
        if taskReferences.isEmpty {
            try? FileManager.default.removeItem(atPath: Storage.uploadTasksFile)
            return
        }

        let saved = NSKeyedArchiver.archiveRootObject(taskReferences, toFile: Storage.uploadTasksFile)
        if !saved {
            print("Upload Tasks: Error saving pending tasks to disk")
            return
        }
        
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var fileUrl = URL(fileURLWithPath: Storage.uploadTasksFile)
        try? fileUrl.setResourceValues(resourceValues)
    }
    
    // MARK: Generic dataTask handling
    
    private func dataTask(context: APIContext, endpoint: String, parameters: [String : Any]?, method: HTTPMethod, completion:@escaping (AnyObject?, Error?) -> ()) {
        
        var request = URLRequest(url: URL(string: baseURLString(for: context) + endpoint)!)
        
        request.httpMethod = method.rawValue
        
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        switch method {
        case .get:
            if parameters != nil {
                var components = URLComponents(string: request.url!.absoluteString)
                var items = [URLQueryItem]()
                for (key, value) in parameters! {
                    var itemValue = ""
                    if let value = value as? String {
                        itemValue = value
                    } else if let value = value as? Int {
                        itemValue = String(value)
                    } else {
                        fatalError("API client: Unsupported parameter type")
                    }
                    
                    let item = URLQueryItem(name: key, value: itemValue)
                    items.append(item)
                }
                components?.queryItems = items
                request.url = components?.url
            }
        case .post:
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let parameters = parameters {
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
                } catch let error {
                    print(error.localizedDescription)
                }
            }
        default:
            fatalError("API client: Unsupported HTTP method")
        }
        
        urlSession.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                let error = error as NSError?
                switch error!.code {
                case Int(CFNetworkErrors.cfurlErrorBadServerResponse.rawValue):
                    completion(nil, APIClientError.server(code: 500, message: ""))
                case Int(CFNetworkErrors.cfurlErrorSecureConnectionFailed.rawValue) ..< Int(CFNetworkErrors.cfurlErrorUnknown.rawValue):
                    completion(nil, APIClientError.connection)
                default:
                    completion(nil, APIClientError.server(code: error!.code, message: error!.localizedDescription))
                }
                return
            }
            
            guard let data = data else {
                completion(nil, error)
                return
            }
            
            // Attempt parsing to JSON
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                // Check if there's an error in the response
                if let responseDictionary = json as? [String: AnyObject],
                    let errorDict = responseDictionary["error"] as? [String : AnyObject],
                    let errorMessage = (errorDict["message"] as? [AnyObject])?.last as? String {
                    completion(nil, APIClientError.server(code: (response as? HTTPURLResponse)?.statusCode ?? 0, message: errorMessage))
                } else {
                    completion(json as AnyObject, nil)
                }
            } else if let image = UIImage(data: data) { // Attempt parsing UIImage
                completion(image, nil)
            } else { // Parsing error
                if let stringData = String(data: data, encoding: String.Encoding.utf8) {
                    print("API: \(stringData)")
                }
                completion(nil, APIClientError.parsing)
            }
            
            }.resume()
    }

    // MARK: - Public methods
    func post(context: APIContext, endpoint: String, parameters: [String : Any]?, completion:@escaping (AnyObject?, Error?) -> ()) {
        dataTask(context: context, endpoint: endpoint, parameters: parameters, method: .post, completion: completion)
    }
    
    func get(context: APIContext, endpoint: String, parameters: [String : Any]?, completion:@escaping (AnyObject?, Error?) -> ()) {
        dataTask(context: context, endpoint: endpoint, parameters: parameters, method: .get, completion: completion)
    }
    
    func put(context: APIContext, endpoint: String, parameters: [String : Any]?, completion:@escaping (AnyObject?, Error?) -> ()) {
        dataTask(context: context, endpoint: endpoint, parameters: parameters, method: .put, completion: completion)
    }
    
    func uploadImage(_ data: Data, imageName: String, imageType: ImageType = .jpeg, context: APIContext, endpoint: String, completion:@escaping (AnyObject?, Error?) -> ()) {
        let boundaryString = "Boundary-\(NSUUID().uuidString)"
        let fileUrl = createFileWith(imageData: data, imageName: imageName, imageType: imageType, boundaryString: boundaryString)
    
        var request = URLRequest(url: URL(string: baseURLString(for: context) + endpoint)!)
        
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundaryString)", forHTTPHeaderField:"content-type")
        
        URLSession.shared.uploadTask(with: request, fromFile: fileUrl) { (data, response, error) in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
                DispatchQueue.main.async { completion(nil, error) }
                return
            }
            
            DispatchQueue.main.async { completion(json as AnyObject, nil) }
            
        }.resume()
    }
    
    func uploadImage(_ image: UIImage, imageName: String, imageType: ImageType = .jpeg, context: APIContext, endpoint: String, completion:@escaping (AnyObject?, Error?) -> ()) {
        
        guard let imageData = imageData(withImage: image, forType: imageType) else {
            print("Image Upload: cannot read image data")
            completion(nil, nil)
            return
        }
        
        uploadImage(imageData, imageName: imageName, context: context, endpoint: endpoint, completion: completion)
    }
    
    func uploadImage(_ data: Data, imageName: String, imageType: ImageType = .jpeg, reference: String?, context: APIContext, endpoint: String) {
        let boundaryString = "Boundary-\(NSUUID().uuidString)"
        let fileUrl = createFileWith(imageData: data, imageName: imageName, imageType: imageType, boundaryString: boundaryString)
        
        var request = URLRequest(url: URL(string: baseURLString(for: context) + endpoint)!)
        
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundaryString)", forHTTPHeaderField:"content-type")
        
        let dataTask = backgroundUrlSession.uploadTask(with: request, fromFile: fileUrl)
        if reference != nil {
            taskReferences[dataTask.taskIdentifier] = reference
        }
        
        dataTask.resume()
    }
    
    func uploadImage(_ image: UIImage, imageName: String, imageType: ImageType = .jpeg, reference: String?, context: APIContext, endpoint: String) {
        
        guard let imageData = imageData(withImage: image, forType: imageType) else {
            print("Image Upload: cannot read image data")
            return
        }
        
        uploadImage(imageData, imageName: imageName, imageType: imageType, reference: reference, context: context, endpoint: endpoint)
    }
    
    func uploadImage(_ file: URL, reference: String?, context: APIContext, endpoint: String) {
        guard let fileData = try? Data(contentsOf: file) else {
            print("File Upload: cannot read file data")
            return
        }

        let imageName = file.lastPathComponent
        
        var imageType:ImageType = .jpeg
        if imageName.lowercased().hasSuffix(".png") { imageType = .png } //it's actually a png
        
        uploadImage(fileData, imageName: imageName, imageType: imageType, reference: reference, context: context, endpoint: endpoint)
    }
    
    func pendingBackgroundTaskCount(_ completion: @escaping ((Int)->Void)) {
        backgroundUrlSession.getAllTasks { completion($0.count) }
    }
}

extension APIClient: URLSessionDelegate, URLSessionDataDelegate {
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let completionHandler = backgroundSessionCompletionHandler {
            completionHandler()
            backgroundSessionCompletionHandler = nil
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else {
            if let stringData = String(data: data, encoding: String.Encoding.utf8) {
                print("API Error: \(stringData)")
            }
            return
        }
        
        // Add reference to response dictionary if there is one
        if let reference = taskReferences[dataTask.taskIdentifier] {
            taskReferences[dataTask.taskIdentifier] = nil
            
            json!["task_reference"] = reference as AnyObject
        }
        NotificationCenter.default.post(name: APIClient.backgroundSessionTaskFinished, object: nil, userInfo: json)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard session.configuration.identifier != nil else { return }
        
        if error != nil {
            let error = error as NSError?
            var userInfo = [ "error": APIClientError.server(code: error!.code, message: error!.localizedDescription) ] as [String: AnyObject]
            
            // Add reference to response dictionary if there is one
            if let reference = taskReferences[task.taskIdentifier] {
                taskReferences[task.taskIdentifier] = nil

                userInfo["task_reference"] = reference as AnyObject
            }
            
            NotificationCenter.default.post(name: APIClient.backgroundSessionTaskFinished, object: nil, userInfo: userInfo)
        }
    }
}
