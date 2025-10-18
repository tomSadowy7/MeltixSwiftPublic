//
//  SprinklerControlPopup.swift
//  meltixswift
//
//  Created by Tomasz Sadowy on 6/14/25.
//

//
//  SprinklerControlPopup.swift
//

import SwiftUI

struct SprinklerControlPopup: View {
    let device: Device                       // injected from sheet(item:)
    @State private var zones = Array(repeating: false, count: 4)
    
    var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<4, id: \.self) { idx in
                    Toggle("Zone \(idx + 1)", isOn: $zones[idx])
                        .onChange(of: zones[idx]) { newValue in
                            send(zone: idx + 1, on: newValue)
                        }
                }
            }
            .navigationTitle(device.name)
        }
    }
    
    private func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
    
    // MARK: REST  – very thin wrapper / demo
    private func send(zone: Int, on: Bool) {
        guard let tok = AuthManager.shared.token,
              let url = URL(string: "\(AuthManager.shared.baseURL)/sprinkler/\(device.id)/zone/\(zone)/\(on ? "on" : "off")")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req).resume()
    }
}
