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
    @State private var fileImporterPresented = false
    private let certificateFiles = [UTType(filenameExtension: "cer")!]
    
    var body: some View {
        VStack {
            HStack {
                Text(LocalizedStringKey("APNS certificate file(.cer)"))
                TextField(LocalizedStringKey("pick a certificate file(.cer)"), text: $model.certificateFile)
                Button(LocalizedStringKey("browse ...")) {
                    fileImporterPresented = true
                }
            }.fileImporter(isPresented: $fileImporterPresented, allowedContentTypes: certificateFiles) { result in
                if let url = try? result.get() {
                    model.certificateFile = url.path
                }
            }
            
            TokenList(model: self.model)
            
            HStack(spacing:40) {
                Picker(LocalizedStringKey("priority"), selection: $model.priority) {
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
                    HStack {
                        Image(systemName: "minus.circle")
                            .onTapGesture {
                                self.model.deviceTokens.remove(at: index)
                            }
                        Text(model.deviceTokens[index].token)
                        Spacer()
                        Toggle("", isOn: $model.deviceTokens[index].selected)
                        Image(systemName: model.deviceTokens[index].pushStateImageName)
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
        self.newToken = ""
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
