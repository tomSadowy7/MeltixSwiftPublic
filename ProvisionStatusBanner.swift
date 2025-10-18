//
//  ProvisionStatusBanner.swift
//  meltixswift
//
//  Created by Tomasz Sadowy on 6/14/25.
//


//
//  ProvisionStatusBanner.swift
//  MeltixSwift
//

import SwiftUI
import Combine

/// A slim, non-dismissable bar that lives at the bottom of
/// *HomeBaseDevicesView* while the Pi is in provisioning-mode.
struct ProvisionStatusBanner: View {

    /// Shown/hidden by the parent view
    @Binding var isVisible: Bool
    /// Fired when provisioning succeeds and a device arrives
    var onSuccess: (Device) -> Void

    // -- State internal to the banner
    @State private var isScanning = true
    @State private var timedOut   = false
    @State private var bag = Set<AnyCancellable>()

    // MARK: UI
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: iconName)
                .foregroundColor(.gold)

            // Text
            Text(statusText)
                .foregroundColor(.white)
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            // Spinner while actively scanning
            if isScanning && !timedOut {
                ProgressView().tint(.gold)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.charcoal)
        .cornerRadius(14)
        .shadow(radius: 6)
        .padding(.horizontal)
        .onAppear(perform: begin)
    }

    // MARK: Helpers
    private var iconName: String {
        if isScanning { return "antenna.radiowaves.left.and.right" }
        return timedOut ? "exclamationmark.triangle.fill"
                        : "checkmark.seal.fill"
    }

    private var statusText: String {
        if isScanning && !timedOut { return "Scanning for new device…" }
        if timedOut                 { return "No device responded."    }
        return "Device paired!"
    }

    private func begin() {
        connectSocketIfNeeded()
        subscribeToSocket()
        triggerProvision()

        // 30 s timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if isScanning {
                isScanning = false
                timedOut   = true
                cleanUp()
            }
        }
    }

    // ——— Socket
    private func connectSocketIfNeeded() {
        if let jwt = AuthManager.shared.token,
           let hb  = AuthManager.shared.homeBaseId {
            DeviceWebSocketManager.shared.connectIfNeeded(jwt: jwt,
                                                          homebaseId: hb)
        }
    }

    private func subscribeToSocket() {
        DeviceWebSocketManager.shared.$lastProvisionedDevice
            .compactMap { $0 }
            .sink { dev in
                print("[Banner] got device \(dev)")
                isScanning = false
                timedOut   = false
                onSuccess(dev)
                cleanUp()
            }
            .store(in: &bag)
    }

    private func triggerProvision() {
        guard let tok = AuthManager.shared.token,
              let url = URL(string:"\(AuthManager.shared.baseURL)/homebase/start-device-provision")
        else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r).resume()
    }

    // Close socket & hide banner
    private func cleanUp() {
        DeviceWebSocketManager.shared.disconnectAndClear()
        bag.removeAll()

        // Let animation finish, then slide out
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { isVisible = false }
        }
    }
}
