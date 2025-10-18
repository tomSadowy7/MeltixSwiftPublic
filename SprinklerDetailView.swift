import SwiftUI

struct SprinklerDetailView: View {
    
    let device: Device
    @EnvironmentObject private var auth: AuthManager
    
    @State private var zones = [false, false, false, false]
    @State private var loading = true
    @State private var zoneLoading = [false, false, false, false]
    @State private var showToast = false
    @State private var toastMsg = ""

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                // ────────── Header ──────────
                VStack(spacing: 4) {
                    Image(systemName: "leaf.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.gold)
                    Text(device.name).font(.title3.weight(.bold))
                    Text(device.id).font(.caption).foregroundColor(.gray)
                }
                .padding(.top, 8)
                
                Divider().background(Color.gold.opacity(0.5))
                
                // ────────── Toggles ──────────
                if loading {
                    ProgressView().tint(.gold)
                } else {
                    VStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { idx in
                            HStack {
                                Text("Zone \(idx + 1)")
                                    .foregroundColor(.white)
                                
                                Spacer()

                                if zoneLoading[idx] {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(.gold)
                                        .padding(.trailing, 4)
                                }

                                Toggle("", isOn: Binding(
                                    get: { zones[idx] },
                                    set: { newVal in updateZone(idx, to: newVal) }
                                ))
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: .gold))
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.jetBlack.ignoresSafeArea())
            .task { await fetchState() }

            // ────────── Top Toast Overlay ──────────
            if showToast {
                VStack {
                    Text(toastMsg)
                        .font(.callout.bold())
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                        .shadow(radius: 8)
                        .padding(.top, 18)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showToast = false }
                    }
                }
            }
        }
    }

    func updateZone(_ idx: Int, to newVal: Bool) {
        Task {
            zoneLoading[idx] = true
            let success = await sendZone(idx + 1, to: newVal)
            zoneLoading[idx] = false
            if success {
                zones[idx] = newVal
            } else {
                toastMsg = "Sprinkler zone update failed."
                withAnimation { showToast = true }
            }
        }
    }
}

// MARK: – Networking
private extension SprinklerDetailView {
    
    @MainActor
    func fetchState() async {
        guard let url = URL(string: "\(auth.baseURL)/sprinkler/\(device.id)"),
              let token = auth.token else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let state = try JSONDecoder().decode(SprinklerStateDTO.self, from: data)
            zones = [state.zone1, state.zone2, state.zone3, state.zone4]
        } catch {
            print("[Sprinkler] failed to fetch state:", error)
        }
        loading = false
    }

    func sendZone(_ zone: Int, to on: Bool) async -> Bool {
        guard let url = URL(string: "\(auth.baseURL)/sprinkler/\(device.id)/zone/\(zone)"),
              let token = auth.token else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(ZoneCmd(on: on))

        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            return (res as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[Sprinkler] Zone \(zone) toggle failed:", error)
            return false
        }
    }

    struct SprinklerStateDTO: Decodable {
        let zone1: Bool, zone2: Bool, zone3: Bool, zone4: Bool
    }
    struct ZoneCmd: Encodable { let on: Bool }
}
