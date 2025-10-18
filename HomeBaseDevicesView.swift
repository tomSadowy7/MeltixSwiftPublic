//
//  HomeBaseDevicesView.swift
//  MeltixSwift
//

import SwiftUI
import Combine

struct HomeBaseDevicesView: View {

    // MARK: – State / Env
    @EnvironmentObject private var auth : AuthManager
    @StateObject  private var wsMgr = DeviceWebSocketManager.shared

    @State private var devices      : [Device] = []
    //@State private var isLoading    = false
    @State private var bannerText   : String? = nil
    @State private var showDetail   : Device? = nil
    @State private var showSchedules: Device? = nil
    @State private var showProvisionBar = false
    @State private var showAccountSettings = false

    @State private var bag = Set<AnyCancellable>()

    // MARK: – Body
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                //──────── MAIN CONTENT ────────
                VStack(spacing: 18) {
                    header
                    deviceList
                }
                .padding(.horizontal)
                .navigationBarTitleDisplayMode(.inline)

                //──────── Slide-down banner ────────
                if let bannerText {
                    banner(text: bannerText)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                }

                //──────── Provision bar (bottom) ────────
                if showProvisionBar {
                    ProvisionStatusBanner(isVisible: $showProvisionBar) { dev in
                        bannerText = "Paired “\(dev.name)”!"
                        Task { await fetchDevices() }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                    .zIndex(3)
                }
            }
        }
        .task { await firstLaunch() }
        .sheet(item: $showDetail) { dev in
            SprinklerDetailView(device: dev)
                .presentationDetents([.height(360)])
        }
        .sheet(item: $showSchedules) { dev in
            ScheduleListView(device: dev)
                .presentationDetents([.medium])   // Only medium, disables drag-to-resize
                .interactiveDismissDisabled(false) // Keep as desired
        }
        .sheet(isPresented: $showAccountSettings) {
            AccountSettingsView(onClose: { showAccountSettings = false })
                .environmentObject(auth)          // ← inject it here
        }
    }

    // MARK: – Header
    private var header: some View {
        HStack {
            // Left: Account settings
            Button {
                showAccountSettings = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22))
            }
            .foregroundColor(.gold)

            // Middle: Add device
            Button {
                withAnimation { showProvisionBar = true }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
            }
            .foregroundColor(.gold)
            .padding(.leading, 10)

            Spacer()

            // Title
            Text("My Devices")
                .font(.title2.bold())
                .foregroundColor(.gold)

            Spacer()

            // Right: Logout
            Button("Logout") {
                auth.logout()
            }
            .font(.callout.weight(.medium))
            .foregroundColor(.gold)
        }
    }
    @ViewBuilder
    private var deviceList: some View {
        Group {
            if devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName:"antenna.radiowaves.left.and.right")
                        .font(.system(size: 42))
                        .foregroundColor(.darkGold)
                    Text("No devices found")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(devices) { dev in
                            DeviceRow(device: dev,
                                      onManual:    { showDetail   = dev },
                                      onSchedules: { showSchedules = dev })
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .refreshable {
                    await fetchDevices()
                }
            }
        }
    }

    // MARK: – Toolbar
    @ToolbarContentBuilder private var logoutTool: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Logout") { auth.logout() }
                .foregroundColor(.gold)
        }
    }

    // MARK: – Slide-down banner
    @ViewBuilder private func banner(text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.gold)
            .cornerRadius(14)
            .shadow(radius: 4)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { bannerText = nil }
                }
            }
            .padding(.top, 6)
    }
}

// MARK: – Networking & Start-up
private extension HomeBaseDevicesView {

    func firstLaunch() async {
        if auth.homeBaseId == nil { await fetchHomebaseId() }
        await fetchDevices()
        
        wsMgr.$lastProvisionedDevice
            .compactMap { $0 }
            .sink { _ in
                Task {
                    await fetchDevices()
                }
            }
            .store(in: &bag)
    }

    func fetchDevices() async {
        guard let tok = auth.token,
              let url = URL(string: "\(auth.baseURL)/device/list") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let res = try? JSONDecoder().decode(DeviceListResponse.self, from: data) {
                print("Old:", devices)
                print("New:", res.devices)
                await MainActor.run { devices = res.devices }
            }
        } catch {
            print("Fetch failed:", error)
        }
    }
    

    func fetchHomebaseId() async {
        guard let tok = auth.token,
              let url = URL(string: "\(auth.baseURL)/homebase/getname") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let res = try? JSONDecoder().decode(AuthManager.HomeBaseResponse.self, from: data),
           let id = res.id {
            await MainActor.run { auth.homeBaseId = id }
        }
    }
}

// MARK: – Row
private struct DeviceRow: View {
    let device: Device
    let onManual: () -> Void
    let onSchedules: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Top info row ──
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(device.online ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                    Circle()
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).fontWeight(.semibold).foregroundColor(.white)
                    Text(device.type.capitalized).font(.subheadline).foregroundColor(.gold)
                    Text(device.id).font(.caption2).foregroundColor(.gray)
                }
                Spacer()
            }

            Divider().background(Color.gold.opacity(0.25))

            // ── Action buttons ──
            HStack(spacing: 12) {
                Button("Manual", action: onManual)
                    .buttonStyle(GoldFilledButtonStyle())
                    .disabled(!device.online)
                    .opacity(device.online ? 1 : 0.4)

                Button("Schedules", action: onSchedules)
                    .buttonStyle(GoldFilledButtonStyle())
                    .disabled(!device.online)
                    .opacity(device.online ? 1 : 0.4)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.charcoalGray)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gold.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
    }
}
// MARK: – DTO
struct DeviceListResponse: Codable {
    let success : Bool
    let devices : [Device]
}

struct GoldFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)      // ← equal height
            .background(Color.gold.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundColor(.black)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.darkGold, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GoldOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)      // ← same height
            .background(Color.charcoalGray.opacity(configuration.isPressed ? 0.4 : 0.3))
            .foregroundColor(.gold)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gold, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
