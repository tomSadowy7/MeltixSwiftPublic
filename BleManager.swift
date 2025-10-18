import CoreBluetooth
import Combine
import OSLog

final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    private let logger = Logger(subsystem: "com.your.app", category: "BLE")
    
    // MARK: - UUID Configuration
    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    private let ssidUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef1")
    private let passwordUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef2")
    private let statusUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef3")
    private let tokenUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef5")
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var bleStatus = "Disconnected"
    @Published var provisioningStatus = "Ready"
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var debugLogs: [String] = []
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics = [CBUUID: CBCharacteristic]()
    private var connectionTimer: Timer?
    private var keepaliveTimer: Timer?
    private var expectedStatusSequence = [UInt8]()
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
        log("BLE Manager initialized")
    }
    
    // MARK: - Public Methods
    func reset() {
        log("Resetting BLE Manager")
        stopTimers()
        
        if centralManager.state == .poweredOn, let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            centralManager.stopScan()
        }
        
        peripheral = nil
        characteristics.removeAll()
        expectedStatusSequence.removeAll()
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.bleStatus = "Disconnected"
            self.provisioningStatus = "Try Again"
        }
    }
    
    func startScan() {
        guard centralManager.state == .poweredOn else {
            log("Bluetooth is not powered on")
            DispatchQueue.main.async {
                self.bleStatus = "Bluetooth off"
            }
            return
        }
        
        log("Starting scan for peripherals")
        reset()
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
            CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [serviceUUID]
        ])
        
        DispatchQueue.main.async {
            self.bleStatus = "Scanning..."
            self.provisioningStatus = ""
        }
    }
    
    func provision(ssid: String, password: String) {
        log("Provisioning requested for SSID: \(ssid)")
        
        Task {
            let token: String? = await MainActor.run {
                let token = AuthManager.shared.token
                log("Retrieved token: \(token != nil ? "***REDACTED***" : "nil")")
                return token
            }
            
            guard let peripheral = self.peripheral,
                  let ssidChar = self.characteristics[self.ssidUUID],
                  let passwordChar = self.characteristics[self.passwordUUID],
                  let tokenChar = self.characteristics[self.tokenUUID],
                  let token, !token.isEmpty else {
                
                let missing = [
                    peripheral == nil ? "Peripheral" : nil,
                    characteristics[self.ssidUUID] == nil ? "SSID Characteristic" : nil,
                    characteristics[self.passwordUUID] == nil ? "Password Characteristic" : nil,
                    characteristics[self.tokenUUID] == nil ? "Token Characteristic" : nil,
                    token == nil ? "Token (nil)" : nil,
                    token?.isEmpty == true ? "Token (empty)" : nil
                ].compactMap { $0 }
                
                log("Provisioning failed - Missing: \(missing.joined(separator: ", "))")
                DispatchQueue.main.async {
                    self.provisioningStatus = "Error: Missing credentials or BLE characteristics"
                }
                return
            }
            
            DispatchQueue.main.async {
                self.provisioningStatus = "Sending credentials..."
            }
            
            // Expected status sequence
            expectedStatusSequence = [0x01, 0x02, 0x03]
            
            // Write credentials
            let credentials: [(Data, CBCharacteristic, String)] = [
                (Data(ssid.utf8), ssidChar, "SSID"),
                (Data(password.utf8), passwordChar, "Password"),
                (Data(token.utf8), tokenChar, "Token")
            ]
            
            for (data, characteristic, description) in credentials {
                log("Writing \(description) (\(data.count) bytes) to \(characteristic.uuid)")
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
            
            startConnectionTimer()
        }
    }
    
    // MARK: - Private Methods
    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let logMessage = "[\(timestamp)] \(message)"
        logger.debug("\(logMessage)")
        DispatchQueue.main.async {
            self.debugLogs.append(logMessage)
            if self.debugLogs.count > 100 { self.debugLogs.removeFirst() }
        }
    }
    
    private func startConnectionTimer() {
        stopTimers()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.log("Connection timeout - resetting")
            self?.reset()
            DispatchQueue.main.async {
                self?.provisioningStatus = "Error: Timeout waiting for response"
            }
        }
        startKeepaliveTimer()
    }
    
    private func startKeepaliveTimer() {
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, let peripheral = self.peripheral, let statusChar = self.characteristics[self.statusUUID] else { return }
            self.log("Sending keepalive ping")
            peripheral.readValue(for: statusChar)
        }
    }
    
    private func stopTimers() {
        connectionTimer?.invalidate()
        keepaliveTimer?.invalidate()
        connectionTimer = nil
        keepaliveTimer = nil
    }
    
    private func handleStatusUpdate(_ value: UInt8) {
        log("Received status: 0x\(String(format: "%02X", value))")
        
        // Validate expected sequence
        if let expected = expectedStatusSequence.first, expected == value {
            expectedStatusSequence.removeFirst()
        } else {
            log("Unexpected status sequence. Expected: \(expectedStatusSequence.map { String(format: "0x%02X", $0) })")
        }
        
        DispatchQueue.main.async {
            switch value {
            case 0x01:
                self.provisioningStatus = "Connecting to WiFi..."
            case 0x02: //if Wifi was successful
                self.provisioningStatus = "Registering..."
            case 0x03:
                self.stopTimers()
                self.provisioningStatus = "HomeBase claimed!"
                NotificationCenter.default.post(name: .homeBaseClaimed, object: nil)
            case 0x04:
                self.provisioningStatus = "WiFi failed"
                // Do NOT call self.reset()
                NotificationCenter.default.post(name: .provisioningFailed, object: nil)
            case 0x05:
                self.provisioningStatus = "Claim failed"
                NotificationCenter.default.post(name: .provisioningFailed, object: nil)
            default:
                self.log("Unknown status: 0x\(String(format: "%02X", value))")
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: String = {
            switch central.state {
            case .poweredOn: return "Powered On"
            case .poweredOff: return "Powered Off"
            case .resetting: return "Resetting"
            case .unauthorized: return "Unauthorized"
            case .unknown: return "Unknown"
            case .unsupported: return "Unsupported"
            @unknown default: return "Unknown State"
            }
        }()
        log("Bluetooth state: \(state)")
        
        DispatchQueue.main.async {
            self.bleStatus = central.state == .poweredOn ? "" : "Bluetooth \(state)"
            if central.state != .poweredOn { self.reset() }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown"
        log("Discovered peripheral: \(name) (\(peripheral.identifier))")
        
        DispatchQueue.main.async {
            if !self.discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discoveredPeripherals.append(peripheral)
            }
        }
        
        if name == "WiFi Config" || name == "raspberrypi" { //Fix to only take WiFi Config later
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            log("Connecting to \(name)...")
            DispatchQueue.main.async {
                self.bleStatus = "Connecting..."
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Connected to \(peripheral.name ?? "peripheral")")
        DispatchQueue.main.async {
            self.isConnected = true
            self.bleStatus = "Discovering services..."
        }
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Connection failed: \(error?.localizedDescription ?? "Unknown error")")
        reset()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let reason = error?.localizedDescription ?? "Intentional"
        log("Disconnected. Reason: \(reason). Last status: \(provisioningStatus)")
        reset()
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("Service discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            log("No services found")
            return
        }
        
        log("Discovered \(services.count) services")
        services.forEach { service in
            log("Discovering characteristics for \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            log("No characteristics found")
            return
        }
        
        characteristics.forEach { characteristic in
            self.characteristics[characteristic.uuid] = characteristic
            log("Found characteristic: \(characteristic.uuid)")
            
            if characteristic.uuid == statusUUID {
                log("Enabling notifications for status")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        
        // Check if all required characteristics are available
        let required = [ssidUUID, passwordUUID, tokenUUID, statusUUID]
        let missing = required.filter { self.characteristics[$0] == nil }
        
        if missing.isEmpty {
            log("All required characteristics discovered")
            DispatchQueue.main.async {
                self.bleStatus = "HomeBase Detected"
                self.provisioningStatus = "Ready to provision"
            }
        } else {
            log("Missing characteristics: \(missing.map { $0.uuidString }.joined(separator: ", "))")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Notification setup failed for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        log("Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Value update failed for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            log("Received empty data for \(characteristic.uuid)")
            return
        }
        
        log("Received \(data.count) bytes from \(characteristic.uuid): \(data.hexEncodedString())")
        
        if characteristic.uuid == statusUUID, !data.isEmpty {
            handleStatusUpdate(data[0])
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Write failed for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            log("Write succeeded for \(characteristic.uuid)")
        }
    }
}

// MARK: - Extensions
extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

extension Notification.Name {
    static let homeBaseClaimed = Notification.Name("com.your.app.homeBaseClaimed")
    static let provisioningFailed = Notification.Name("com.your.app.provisioningFailed")
}
