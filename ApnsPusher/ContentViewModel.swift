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
    static let connectionTechs = [
        NSLocalizedString("JWT", comment: ""),
        NSLocalizedString("certifcate", comment: "")]
    static let defaultPayload =
    """
    {
        "aps": {
            "alert" : {
                "title" : "Push message",
                "subtitle" : "Test push notification",
                "body" : "You can handle it or dismiss"
            },
            "badge": 6,
            "sound": "default"
        }
    }
    """
    
    @Published var connectionTech = ContentViewModel.connectionTechs[0]
    @Published var p8File = ""
    @Published var keyID = ""
    @Published var teamID = ""
    
    @Published var certificateFile = ""
    @Published var deviceTokens = Array<DeviceToken>()
    @Published var priority = 5
    @Published var collapseID = ""
    @Published var topic = ""
    @Published var payloadType = ContentViewModel.payloadTypes[0]
    @Published var apiPath = sandboxAPI
    @Published var log = NSLocalizedString("ready", comment: "")
    @Published var hasError = false
    
    @Published var payload = ""
    
    private let sessionDelegate = SessionDelegate()
    private let session: URLSession
    private var keychain: SecKeychain?
    private var cancellableSet = Set<AnyCancellable>()
    private var keyFromP8: String = ""
    private let jwtCache = JWTCache()
    
    init() {
        SecKeychainCopyDefault(&keychain)
        session = URLSession(configuration: URLSessionConfiguration.default,
                             delegate: sessionDelegate,
                             delegateQueue: nil)        
        
        subscribe()
        load()
    }
    
    var isTokenBased: Bool {
        connectionTech == ContentViewModel.connectionTechs[0]
    }
    
    private func subscribe() {
        $certificateFile.sink { [unowned self] value in
            self.sessionDelegate.secIdentify = nil
        }.store(in: &cancellableSet)
        
        $connectionTech.sink { [unowned self] value in
            self.sessionDelegate.tokenBased = value == ContentViewModel.connectionTechs[0]
        }.store(in: &cancellableSet)
        
        $p8File.sink { [unowned self] value in
            self.keyFromP8 = ""
        }.store(in: &cancellableSet)
    }
    
    func send() {
        guard verifyParameters() else {
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
        
        self.sendRequest(request, to: deviceToken)
    }
    
    private func sendRequest(_ request: URLRequest, to deviceToken: DeviceToken) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
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
       
        task.resume()
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
        if self.isTokenBased {
            request.addValue("bearer \(jwtCache.getSignature())", forHTTPHeaderField: "authorization")
        }
        return request
    }
    
    private func payloadData() -> Data? {
        // try converting payload string to single line string
        guard let data = payload.data(using: String.Encoding.utf8) else {
            return nil
        }
        guard let jsonObj = try? JSONSerialization.jsonObject(with: data,
                                                              options: .mutableContainers) else {
            return data
        }

        return try? JSONSerialization.data(withJSONObject: jsonObj)
    }
    
    private func verifyParameters() -> Bool {
        if topic.isEmpty {
            setLog(NSLocalizedString("topic required", comment: ""))
            return false
        }
        
        if self.deviceTokens.isEmpty {
            setLog(NSLocalizedString("device token required", comment: ""))
            return false
        }
        
        let tokenBased = self.connectionTech == ContentViewModel.connectionTechs[0]
        
        if tokenBased {
            if !self.tryOpenP8() {
                return false
            }
            if self.keyID.count != 10 {
                setLog(NSLocalizedString("key ID required", comment: ""))
                return false
            }
            if self.teamID.count != 10 {
                setLog(NSLocalizedString("team ID required", comment: ""))
                return false
            }
        } else {
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
        }
        
        jwtCache.update(key: self.keyFromP8, keyID: keyID, teamID: teamID)
        
        return true
    }
    
    private func tryOpenP8() -> Bool {
        guard !self.p8File.isEmpty else {
            setLog(NSLocalizedString("signing key file required", comment: ""))
            return false
        }
        if self.keyFromP8.count > 128 {
            return true
        }
        guard let str = try? String(contentsOf: URL(fileURLWithPath: self.p8File)) else {
            let alert = NSLocalizedString("Unable to open signing key file. Is the file accessible? Try 'browse...' to open it", comment: "")
            setLog(alert)
            return false
        }
        guard str.range(of: "-----BEGIN PRIVATE KEY-----") != nil &&
              str.range(of: "-----END PRIVATE KEY-----") != nil else {
                  setLog(NSLocalizedString("Invalid signing key file.", comment: ""))
                  return false
              }
        
        self.keyFromP8 = str
        return true
    }
    
    private func openCertificate(certFile: String) {
        sessionDelegate.secIdentify = nil
        
        guard !certFile.isEmpty else {
            setLog(NSLocalizedString("certificate file required", comment: ""))
            return
        }
        
        guard let certificateData = try? Data(contentsOf: URL(fileURLWithPath: certFile)) else {
            let alert = NSLocalizedString("Unable to open certificate key file. Is the file accessible? Try 'browse...' to open it", comment: "")
            setLog(alert)
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
        UserDefaults.standard.set(p8File, forKey: "p8File")
        UserDefaults.standard.set(keyID, forKey: "keyID")
        UserDefaults.standard.set(teamID, forKey: "teamID")
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
        p8File = UserDefaults.standard.string(forKey: "p8File") ?? ""
        keyID = UserDefaults.standard.string(forKey: "keyID") ?? ""
        teamID = UserDefaults.standard.string(forKey: "teamID") ?? ""
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
    var tokenBased = true
    
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
            completionHandler(.useCredential, tokenBased ? nil : clientCredential)
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
