import SwiftUI

@main
struct MyApp: App {
    @StateObject var authManager = AuthManager.shared
    @StateObject var bleManager = BLEManager.shared
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(bleManager)
                .onAppear {
                    // Reset BLE state on fresh launch
                    if !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch") {
                        bleManager.reset()
                        authManager.logout()
                        UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
                    }
                }
        }
    }
}
