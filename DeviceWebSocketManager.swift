//
//  DeviceWebSocketManager.swift
//  MeltixSwift
//

import Foundation
import Combine

/// Handles the `/ws/app` socket and delivers `devicePaired` messages.
final class DeviceWebSocketManager: ObservableObject {
    
    // MARK: Singleton
    static let shared = DeviceWebSocketManager()
    private init() {}
    
    // MARK: Published
    @Published var lastProvisionedDevice: Device?
    
    // MARK: Internal
    private var task: URLSessionWebSocketTask?
    private var isConnected = false
    
    /// Opens (or re-uses) the socket and registers for provisioning events.
    func connect(token: String, homebaseId: String) {
        guard !isConnected else {
            print("[WS] Already connected")
            return
        }
        guard let url = URL(string: "ws://192.168.68.68:8082/ws/app?token=\(token)") else { return }
        
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        
        // Send registration message
        let payload: [String: Any] = ["type": "watchProvisioning",
                                      "homebaseId": homebaseId]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str  = String(data: data, encoding: .utf8) {
            task?.send(.string(str)) { err in
                if let err { print("[WS] send error:", err) }
                else       { print("[WS] watchProvisioning sent for \(homebaseId)") }
            }
        }
        
        listen()
    }
    
    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }
    
    // MARK: Private receive-loop
    private func listen() {
        task?.receive { [weak self] res in
            guard let self else { return }
            switch res {
            case .failure(let err):
                print("[WS] receive error:", err)
                self.disconnect()                        // will reconnect on next screen load
            case .success(let msg):
                if case .string(let text) = msg { self.handle(text) }
                self.listen()                           // tail-recursion
            }
        }
    }
    
    private func handle(_ raw: String) {
        print("[WS] ↩︎ \(raw)")
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DevicePairedMessage.self, from: data),
              decoded.type == "devicePaired"
        else { return }
        DispatchQueue.main.async { self.lastProvisionedDevice = decoded.device }
    }
}

// MARK: DTO
private struct DevicePairedMessage: Codable {
    let type  : String
    let device: Device
}

extension DeviceWebSocketManager {
    func reset() {
        disconnect()                    // stop the WebSocket
        DispatchQueue.main.async {
            self.lastProvisionedDevice = nil   // clear cached value
        }
    }
}

extension DeviceWebSocketManager {

    /// Open the socket if it isn’t already open.
    /// Safe to call repeatedly.
    func connectIfNeeded(jwt: String, homebaseId: String) {
        if !isConnected {
            connect(token: jwt, homebaseId: homebaseId)
        }
    }

    /// Close the socket **and** forget the last device so the next
    /// provisioning session starts clean.
    func disconnectAndClear() {
        disconnect()
        DispatchQueue.main.async { self.lastProvisionedDevice = nil }
    }
}
