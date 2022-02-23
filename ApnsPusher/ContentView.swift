//
//  ContentView.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/9/28.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model = ContentViewModel()
    
    var body: some View {
        VStack {
            VStack {
                Picker(LocalizedStringKey("Trusted connection"), selection: $model.connectionTech) {
                    ForEach(ContentViewModel.connectionTechs.indices) { i in
                        Text(ContentViewModel.connectionTechs[i])
                            .tag(ContentViewModel.connectionTechs[i])
                    }
                }.frame(width: 300)
                if model.isTokenBased {
                    KeyTokenView(model: self.model)
                } else {
                    CertificateView(model: self.model)
                }
            }
            
            TokenList(model: self.model)
            
            HStack(spacing:40) {
                Picker(LocalizedStringKey("priority"), selection: $model.priority) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("10").tag(10)
                }
                Picker(LocalizedStringKey("payload type"), selection: $model.payloadType) {
                    ForEach(ContentViewModel.payloadTypes.indices) { i in
                        Text(ContentViewModel.payloadTypes[i])
                            .tag(ContentViewModel.payloadTypes[i])
                    }
                }
                Picker(LocalizedStringKey("environment"), selection: $model.apiPath) {
                    Text(LocalizedStringKey("sandbox"))
                        .tag(ContentViewModel.sandboxAPI)
                    Text(LocalizedStringKey("product"))
                        .tag(ContentViewModel.productAPI)
                }
            }
            HStack {
                Text(LocalizedStringKey("collapse ID"))
                TextField(LocalizedStringKey("input collapse ID"), text: $model.collapseID)
                Spacer(minLength: 40)
                Text(LocalizedStringKey("topic (bundle id)"))
                TextField(LocalizedStringKey("input topic here"), text: $model.topic)
            }
            Text(LocalizedStringKey("payload"))
            GeometryReader { proxy in
                TextEditor(text: $model.payload)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }.frame(minHeight: 200)
            
            HStack {
                Text(model.log).foregroundColor(model.hasError ? .red : .green)
                Spacer()
            }.frame(minHeight: 20)
            
            HStack {
                Button(LocalizedStringKey("Send Notification")) {
                    send()
                }
                Spacer()
            }
        }.frame(minWidth: 800).padding()
    }
    
    private func send() {
        model.log = ""
        model.hasError = false
        
        model.send()
    }
}

struct CertificateView: View {
    @ObservedObject var model = ContentViewModel()
    @State private var fileImporterPresented = false
    private let fileExtensions = [UTType(filenameExtension: "cer")!]
    var body: some View {
        HStack {
            Text(LocalizedStringKey("APNS certificate file(.cer)"))
            TextField(LocalizedStringKey("pick a certificate file(.cer)"), text: $model.certificateFile)
            Button(LocalizedStringKey("browse ...")) {
                fileImporterPresented = true
            }
        }.fileImporter(isPresented: $fileImporterPresented, allowedContentTypes: fileExtensions) { result in
            if let url = try? result.get() {
                model.certificateFile = url.path
            }
        }
    }
}

struct TokenList: View {
    @ObservedObject var model = ContentViewModel()
    @State var newToken = ""
    var body: some View {
        VStack {
            Text(LocalizedStringKey("device tokens"))
            List {
                HStack {
                    Image(systemName: "plus.circle")
                        .onTapGesture {
                            self.addToken()
                        }
                    TextField(LocalizedStringKey("paste device token here"), text: $newToken)
                    Spacer()
                }
                
                ForEach(model.deviceTokens.indices, id: \.self) { index in
                    DeviceTokenView(deviceToken: model.deviceTokens[index]) {
                        self.model.deviceTokens.remove(at: index)
                        self.model.save()
                    }
                }
            }.frame(height: 180)
        }
    }
    
    private func addToken() {
        guard !self.newToken.isEmpty else {
            return
        }
        
        self.model.deviceTokens.append(DeviceToken(token: self.newToken))
        self.model.save()
        self.newToken = ""
    }
}

struct DeviceTokenView: View {
    @ObservedObject var deviceToken: DeviceToken
    let onMinus: ()->Void
    
    init(deviceToken: DeviceToken, minusClicked: @escaping ()->Void) {
        self.deviceToken = deviceToken
        self.onMinus = minusClicked
    }
    
    var body: some View {
        HStack {
            Image(systemName: "minus.circle").onTapGesture {
                self.onMinus()
            }
            Text(deviceToken.token)
            Spacer()
            Toggle("", isOn: $deviceToken.selected)
            Image(systemName: deviceToken.pushStateImageName)
        }
    }
}

struct KeyTokenView: View {
    @ObservedObject var model = ContentViewModel()
    @State private var fileImporterPresented = false
    private let fileExtensions = [UTType(filenameExtension: "p8")!]
    var body: some View {
        HStack {
            Text(LocalizedStringKey("signing key file(.p8)"))
            TextField(LocalizedStringKey("pick a signing key file(.p8)"), text: $model.p8File)
            Button(LocalizedStringKey("browse ...")) {
                fileImporterPresented = true
            }
            Text(LocalizedStringKey("key ID"))
            TextField(LocalizedStringKey("input key ID here"), text: $model.keyID)
            Text(LocalizedStringKey("team ID"))
            TextField(LocalizedStringKey("input your team ID here"), text: $model.teamID)
        }.fileImporter(isPresented: $fileImporterPresented, allowedContentTypes: fileExtensions) { result in
            if let url = try? result.get() {
                self.onFilePicked(path: url.path)
            }
        }
    }
    
    private func onFilePicked(path: String) {
        model.p8File = path
        
        // try extracting key ID from file name
        var start = path.lastIndex(of: "/")
        guard start != nil else {
            return
        }
        start = path.index(after: start!)
        guard start != nil else {
            return
        }
        
        let fileName = String(path.suffix(from: start!))
        start = fileName.firstIndex(of: "_")
        guard start != nil else {
            return
        }
        start = fileName.index(after: start!)
        guard start != nil else {
            return
        }
        
        guard let p8Range = fileName.range(of: ".p8", options: .backwards) else {
            return
        }
        
        let subStringRange = Range<String.Index>(uncheckedBounds: (lower: start!, upper: p8Range.lowerBound))
        let keyID = String(fileName[subStringRange])
        self.model.keyID = keyID
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
