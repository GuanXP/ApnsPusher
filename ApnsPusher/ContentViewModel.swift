//
//  ContentViewModel.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/9/28.
//

import Foundation
import CryptoKit
import Combine

class ContentViewModel: ObservableObject {
    static let sandboxAPI =  "https://api.sandbox.push.apple.com"
    static let productAPI = "https://api.push.apple.com"
    static let payloadTypes = ["alert", "background", "voip", "complication", "fileprovider", "mdm"]
    static let defaultPayload =
    """
    {
        "aps":{
            "alert":"The push message by ApnsPusher",
            "badge":6,
            "sound": "default"
        }
    }
    """
    
    @Published var certificateFile = ""
    @Published var deviceTokens = Array<DeviceToken>()
    @Published var priority = 5
    @Published var collapseID = ""
    @Published var topic = ""
    @Published var payloadType = "alert"
    @Published var apiPath = sandboxAPI
    @Published var log = NSLocalizedString("ready", comment: "")
    @Published var hasError = false
    
    @Published var payload = ""
    
    private var sessionDelegate = SessionDelegate()
    private var session: URLSession?
    private var keychain: SecKeychain?
    private var cancellableSet = Set<AnyCancellable>()
    
    init() {
        SecKeychainCopyDefault(&keychain)
        $certificateFile.sink { [unowned self] value in
            self.openCertificate(certFile: value)
        }.store(in: &cancellableSet)
        
        session = URLSession(configuration: URLSessionConfiguration.default,
                             delegate: sessionDelegate,
                             delegateQueue: nil)
        
        load()
    }
    
    func send() {
        guard checkParams() else {
            return
        }
        self.save()

        for deviceToken in deviceTokens {
            if deviceToken.selected {
                self.sendToDevice(deviceToken: deviceToken)
            }
        }
    }
    
    private func sendToDevice(deviceToken: DeviceToken) {
        deviceToken.setPushed(pushed: nil)
        guard let request = makeRequest(deviceToken: deviceToken.token) else {
            return
        }
        guard request.httpBody != nil else {
            self.setLog(NSLocalizedString("Invalid payload format", comment: ""))
            return
        }
        
        let task = session?.dataTask(with: request) { [weak self] data, response, error in
            let resp = response as? HTTPURLResponse
            if resp == nil || error != nil {
                deviceToken.setPushed(pushed: false)
                self?.setLog(error?.localizedDescription ?? NSLocalizedString("Unkown error", comment: ""))
            } else if let data = data {
                if 200 == resp?.statusCode {
                    self?.setLog(NSLocalizedString("Success", comment: ""), isErrorMessage: false)
                    deviceToken.setPushed(pushed: true)
                } else {
                    deviceToken.setPushed(pushed: false)
                    guard let dict = try? JSONSerialization.jsonObject(with: data) as? NSDictionary else {
                        self?.setLog(NSLocalizedString("No data from server", comment: ""))
                        return
                    }
                    let reason = dict["reason"] as? String
                    self?.setLog(reason ?? NSLocalizedString("Unkown error", comment: ""))
                }
            }
        }
       
        task?.resume()
    }
    
    private func makeRequest(deviceToken: String) -> URLRequest? {
        let path = apiPath + "/3/device/\(deviceToken)"
        guard let url = URL(string: path) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payloadData()
        request.addValue(topic, forHTTPHeaderField: "apns-topic")
        
        if !collapseID.isEmpty {
            request.addValue(collapseID, forHTTPHeaderField: "apns-collapse-id")
        }

        request.addValue("\(priority)", forHTTPHeaderField: "apns-priority")
        request.addValue(payloadType, forHTTPHeaderField: "apns-push-type")
        return request
    }
    
    private func payloadData() -> Data? {
        // convert payload string to single line string
        guard let data = payload.data(using: String.Encoding.utf8) else {
            return nil
        }
        guard let jsonObj = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        
        return try? JSONSerialization.data(withJSONObject: jsonObj)
    }
    
    private func checkParams() -> Bool {
        if self.certificateFile.isEmpty {
            setLog(NSLocalizedString("certificate file required", comment: ""))
            return false
        }
        
        if self.sessionDelegate.secIdentify == nil {
            self.openCertificate(certFile: self.certificateFile)
            if self.sessionDelegate.secIdentify == nil {
                setLog(NSLocalizedString("certificate file required", comment: ""))
                return false
            }
        }
        
        if topic.isEmpty {
            setLog(NSLocalizedString("topic required", comment: ""))
            return false
        }
        
        if self.deviceTokens.isEmpty {
            setLog(NSLocalizedString("device token required", comment: ""))
            return false
        }
        
        return true
    }
    
    private func openCertificate(certFile: String) {
        sessionDelegate.secIdentify = nil
        
        guard !certFile.isEmpty else {
            setLog(NSLocalizedString("certificate file required", comment: ""))
            return
        }
        
        guard let certificateData = try? Data(contentsOf: URL(fileURLWithPath: certFile)) else {
            setLog(NSLocalizedString("Unable to open certificate file. Is the file accessible?", comment: ""))
            return
        }
        
        guard let cert = SecCertificateCreateWithData(kCFAllocatorDefault, certificateData as CFData) else {
            setLog(NSLocalizedString("Invalid certificate file", comment: ""))
            return
        }
        
        if let summary = SecCertificateCopySubjectSummary(cert) as String? {
            let header = "Apple Push Services:"
            if let _ = summary.range(of: header) {
                if self.topic.isEmpty { //use topic in certificate if absent
                    self.topic = String(summary.suffix(summary.count - header.count))
                        .trimmingCharacters( in : .whitespaces)
                }
            } else {
                setLog(NSLocalizedString("Invalid certificate file", comment: ""))
                return
            }
        } else {
            setLog(NSLocalizedString("Invalid certificate file", comment: ""))
            return
        }
        
        var secIdentity: SecIdentity?
        SecIdentityCreateWithCertificate(keychain, cert, &secIdentity)
        guard secIdentity != nil else {
            setLog(NSLocalizedString("Unable to create identity with certificate", comment: ""))
            return
        }
        setLog(NSLocalizedString("Certificate loaded", comment: ""), isErrorMessage: false)
        
        sessionDelegate.secIdentify = secIdentity
    }
    
    private func setLog(_ message: String?, isErrorMessage: Bool = true) {
        DispatchQueue.main.async {
            self.log = message ?? ""
            self.hasError = isErrorMessage
        }
    }
}

extension ContentViewModel {
    func save() {
        UserDefaults.standard.set(certificateFile, forKey: "certificateFile")
        UserDefaults.standard.set(self.deviceTokens2StringArray(), forKey: "deviceTokens")
        UserDefaults.standard.set(priority, forKey: "priority")
        UserDefaults.standard.set(collapseID, forKey: "collapseID")
        UserDefaults.standard.set(topic, forKey: "topic")
        UserDefaults.standard.set(payloadType, forKey: "payloadType")
        UserDefaults.standard.set(apiPath, forKey: "apiPath")
        UserDefaults.standard.set(payload, forKey: "payload")
    }
    
    private func load() {
        certificateFile = UserDefaults.standard.string(forKey: "certificateFile") ?? ""
        stringArrayToDeviceTokens(array: UserDefaults.standard.stringArray(forKey: "deviceTokens") ?? [])
        priority = UserDefaults.standard.integer(forKey: "priority")
        if priority == 0 {
            priority = 5
        }
        collapseID = UserDefaults.standard.string(forKey: "collapseID") ?? ""
        let topic = UserDefaults.standard.string(forKey: "topic") ?? ""
        if !topic.isEmpty {
            self.topic = topic
        }
        payloadType = UserDefaults.standard.string(forKey: "payloadType") ?? "alert"
        apiPath = UserDefaults.standard.string(forKey: "apiPath") ?? ContentViewModel.sandboxAPI
        payload = UserDefaults.standard.string(forKey: "payload") ?? ContentViewModel.defaultPayload
    }
    
    private func deviceTokens2StringArray() -> Array<String> {
        return self.deviceTokens.map { $0.toJSON() }
    }
    private func stringArrayToDeviceTokens(array: Array<String>) {
        self.deviceTokens = array.map { DeviceToken.fromJSON(json: $0) }
    }
}

class SessionDelegate: NSObject, URLSessionDelegate {
    private var clientCredential: URLCredential?
    
    var secIdentify: SecIdentity? {
        didSet {
            if let secIdentify = secIdentify {
                var certificate: SecCertificate?
                SecIdentityCopyCertificate(secIdentify, &certificate)
                if let certificate = certificate {
                    clientCredential = URLCredential(identity: secIdentify, certificates: [certificate], persistence: URLCredential.Persistence.forSession)
                }
            } else {
                clientCredential = nil
            }
        }
    }
    
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            completionHandler(.useCredential, clientCredential)
        } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            let serverTrust = challenge.protectionSpace.serverTrust
            let serverCredential = serverTrust != nil ? URLCredential(trust: serverTrust!) : nil
            if serverCredential != nil {
                challenge.sender?.use(serverCredential!, for: challenge)
                completionHandler(.useCredential, serverCredential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}

class DeviceToken: ObservableObject {
    @Published var token: String
    @Published var selected = true
    private var pushed: Bool? = nil
    @Published var pushStateImageName: String = "paperplane.circle"
    
    init(token: String) {
        self.token = token
    }
    
    fileprivate func toJSON() -> String {
        let dict = [
            "token":token,
            "selected": selected
        ] as [String : Any]
        guard let json = try? JSONSerialization.data(withJSONObject: dict) else {
            return ""
        }
        return String(bytes: json, encoding: .utf8) ?? ""
    }
    
    fileprivate static func fromJSON(json: String) -> DeviceToken {
        let deviceToken = DeviceToken(token: "")
        guard let data = json.data(using: .utf8) else {
            return deviceToken
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] else {
            return deviceToken
        }
        deviceToken.token = dict["token"] as? String ?? ""
        deviceToken.selected = dict["selected"] as? Bool ?? false
        return deviceToken
    }
    
    fileprivate func setPushed(pushed: Bool?) {
        DispatchQueue.main.async { [weak self] in
            self?.updatePushed(pushed: pushed)
        }
    }
    private func updatePushed(pushed: Bool?) {
        self.pushed = pushed
        if pushed == nil {
            self.pushStateImageName = "paperplane.circle"
        } else if pushed == true {
            self.pushStateImageName = "checkmark.circle.fill"
        } else {
            self.pushStateImageName = "exclamationmark.circle.fill"
        }
    }
}
