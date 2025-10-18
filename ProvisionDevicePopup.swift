//
//  ProvisionDevicePopup.swift
//  MeltixSwift
//

import SwiftUI
import Combine

struct ProvisionDevicePopup: View {
    
    @Binding var isPresented: Bool
    var onSuccess: (Device) -> Void
    
    @State private var isScanning = true
    @State private var timedOut   = false
    @State private var bag = Set<AnyCancellable>()
    
    var body: some View {
        VStack(spacing: 28) {
            if isScanning && !timedOut {
                ProgressView().tint(.gold)
                Text("Scanning…").foregroundColor(.white)
            } else if timedOut {
                Image(systemName:"exclamationmark.triangle.fill")
                    .font(.system(size:40))
                    .foregroundColor(.gold)
                Text("No device responded.\nTry again?")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
            }
            
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent).tint(.gold)
        }
        .padding(36)
        .background(Color.jetBlack)
        .cornerRadius(14)
        .onAppear { begin() }
    }
    
    // MARK: Flow
    private func begin() {
        
        if let jwt = AuthManager.shared.token,
               let hbId = AuthManager.shared.homeBaseId {
                DeviceWebSocketManager.shared.connectIfNeeded(jwt: jwt, homebaseId: hbId)
            }
        
        subscribe()
        trigger()
        DispatchQueue.main.asyncAfter(deadline: .now()+30) {
            if isScanning { timedOut = true; isScanning = false }
        }
    }
    
    private func subscribe() {
        DeviceWebSocketManager.shared.$lastProvisionedDevice
            .compactMap { $0 }
            .sink { dev in
                print("[Popup] got \(dev)")
                isScanning = false
                timedOut   = false
                onSuccess(dev)
                dismiss()
            }.store(in: &bag)
    }
    
    private func trigger() {
        guard let tok = AuthManager.shared.token,
              let url = URL(string:"\(AuthManager.shared.baseURL)/homebase/start-device-provision") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(tok)", forHTTPHeaderField:"Authorization")
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func dismiss() {
        // 2. close websocket & clear cached device
        cancelProvisionOnServer() 
        DeviceWebSocketManager.shared.disconnectAndClear()

        bag.removeAll()
        isPresented = false
    }
    private func cancelProvisionOnServer() {
        guard let tok = AuthManager.shared.token,
              let url = URL(string: "\(AuthManager.shared.baseURL)/homebase/cancel-device-provision")
        else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req).resume()
    }

}

