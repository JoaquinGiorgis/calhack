import CoreBluetooth
import Foundation
import Observation

/// Text protocol used by the existing ESP32 firmware, with one message per BLE write.
enum WristbandProtocol {
    static let serviceUUID = "6b1a0001-5d1e-4c3b-9a7e-50554e445345"
    static let receiveUUID = "6b1a0002-5d1e-4c3b-9a7e-50554e445345"
    static let maximumMessageBytes = 63
    static let minimumDirectionQuality = 0.60
    private static let numberLocale = Locale(identifier: "en_US_POSIX")

    static func isFresh(validUntil: TimeInterval, now: TimeInterval) -> Bool {
        validUntil.isFinite && now.isFinite && now >= 0 && validUntil > now
    }

    static func alert(event: String, score: Double, angle: Double?, quality: Double?) -> Data? {
        let name = Array(event.utf8)
        guard !name.isEmpty, name.count <= 23,
              name.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }),
              score.isFinite, (0...1).contains(score) else { return nil }
        var text = "E,\(event)," + String(format: "%.2f", locale: numberLocale, score)
        // Direction quality is a heuristic, not a probability. Invalid/weak
        // optional metadata keeps the sound alert but omits the direction.
        if let angle, angle.isFinite, (-180...180).contains(angle),
           let quality, quality.isFinite, (minimumDirectionQuality...1).contains(quality) {
            text += ",\(Int(angle.rounded()))," + String(format: "%.2f", locale: numberLocale, quality)
        }
        return message(text)
    }

    static func level(_ value: Int) -> Data {
        Data("L,\(min(100, max(0, value)))".utf8)
    }

    /// A deliberate training action, not a detected event or dashboard record.
    static func patternTest(event: String) -> Data? {
        guard SoundHapticPattern.all.contains(where: { $0.event == event }) else { return nil }
        return message("P," + event)
    }

    static func time(date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> Data? {
        let formatter = DateFormatter()
        formatter.locale = numberLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        formatter.dateFormat = "EEE, MMM d"
        return message("T,\(time),\(formatter.string(from: date))")
    }

    private static func message(_ text: String) -> Data? {
        let bytes = Data(text.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumMessageBytes,
              bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        return bytes
    }
}

/// No application-level send queue: alerts are submitted immediately or dropped.
/// A successful send means CoreBluetooth accepted the write, not that the motor
/// or display has physically acknowledged it. This firmware has no delivery ACK.
@Observable @MainActor
final class WristbandBluetooth: NSObject {
    private(set) var isConnected = false
    private(set) var connecting = false
    private(set) var status = "Wristband not connected."
    private(set) var settingsDenied = false
    private(set) var unavailableReason: String?
    @ObservationIgnored var onConnect: (() -> Void)?
    @ObservationIgnored var onDisconnect: ((String) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var receiveCharacteristic: CBCharacteristic?
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var responseInFlight = false
    @ObservationIgnored private var connectionTimeout: Task<Void, Never>?
    @ObservationIgnored private var writeTimeout: Task<Void, Never>?

    func connect() {
        guard !isConnected, !connecting else { return }
        if CBManager.authorization == .denied {
            settingsDenied = true
            unavailableReason = "Allow Bluetooth for FortWatch in Settings."
            status = unavailableReason!
            return
        }
        if CBManager.authorization == .restricted {
            settingsDenied = false
            unavailableReason = "Bluetooth is restricted on this iPhone. Check its restrictions."
            status = unavailableReason!
            return
        }
        endSession(message: "Preparing Bluetooth…", notify: false)
        session = UUID()
        wantsConnection = true
        connecting = true
        settingsDenied = false
        unavailableReason = nil
        armConnectionTimeout("Bluetooth did not become ready. Check its permission and reconnect.")
        // Lazy creation: simply opening the app does not request Bluetooth.
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func disconnect() {
        endSession(message: "Wristband disconnected.")
    }

    /// There is no queued alert to replay. An already submitted radio write
    /// cannot be recalled; callers must also invalidate their inference work.
    func clearPendingAlerts() {}

    @discardableResult
    func sendAlert(event: String, score: Double, angle: Double?, quality: Double?,
                   validUntil: TimeInterval) -> Bool {
        guard WristbandProtocol.isFresh(validUntil: validUntil, now: ProcessInfo.processInfo.systemUptime),
              let data = WristbandProtocol.alert(event: event, score: score, angle: angle, quality: quality)
        else { return false }
        return write(data, validUntil: validUntil)
    }

    func sendLevel(_ level: Int) {
        _ = write(WristbandProtocol.level(level))
    }

    @discardableResult
    func sendPatternTest(event: String) -> Bool {
        guard let data = WristbandProtocol.patternTest(event: event) else { return false }
        return write(data, validUntil: ProcessInfo.processInfo.systemUptime + 0.75)
    }

    func sendTime() {
        if let data = WristbandProtocol.time() { _ = write(data) }
    }

    private func write(_ data: Data, validUntil: TimeInterval? = nil) -> Bool {
        guard wantsConnection, isConnected, central?.state == .poweredOn,
              let peripheral, peripheral.state == .connected,
              let characteristic = receiveCharacteristic,
              data.count <= WristbandProtocol.maximumMessageBytes else { return false }
        if let validUntil,
           !WristbandProtocol.isFresh(validUntil: validUntil, now: ProcessInfo.processInfo.systemUptime) {
            return false
        }
        // Keep ordering simple when falling back to acknowledged writes.
        guard !responseInFlight else { return false }
        if characteristic.properties.contains(.writeWithoutResponse),
           peripheral.canSendWriteWithoutResponse,
           data.count <= peripheral.maximumWriteValueLength(for: .withoutResponse) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            return true
        }
        guard characteristic.properties.contains(.write),
              data.count <= peripheral.maximumWriteValueLength(for: .withResponse) else { return false }
        responseInFlight = true
        let run = session
        writeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.session == run, self.responseInFlight else { return }
            self.fail("The wristband did not confirm the message. Move it closer and reconnect.")
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        return true
    }

    private func scan() {
        guard wantsConnection, let central, central.state == .poweredOn else { return }
        connecting = true
        status = "Searching for FortWatch… Turn on the wristband and bring it closer."
        central.scanForPeripherals(withServices: [CBUUID(string: WristbandProtocol.serviceUUID)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        armConnectionTimeout("FortWatch was not found. Turn on the wristband and reconnect.")
    }

    private func armConnectionTimeout(_ message: String) {
        connectionTimeout?.cancel()
        let run = session
        connectionTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.session == run, self.connecting else { return }
            self.fail(message)
        }
    }

    private func fail(_ message: String) {
        endSession(message: message)
        unavailableReason = message
    }

    private func endSession(message: String, notify: Bool = true) {
        let wasReady = isConnected
        session = UUID()
        wantsConnection = false
        isConnected = false
        connecting = false
        receiveCharacteristic = nil
        responseInFlight = false
        connectionTimeout?.cancel()
        connectionTimeout = nil
        writeTimeout?.cancel()
        writeTimeout = nil
        peripheral?.delegate = nil
        if let central {
            central.delegate = nil
            if central.state == .poweredOn {
                central.stopScan()
                if let peripheral { central.cancelPeripheralConnection(peripheral) }
            }
        }
        peripheral = nil
        central = nil
        status = message
        unavailableReason = nil
        if notify && wasReady { onDisconnect?(message) }
    }

    private func current(_ candidate: CBPeripheral) -> Bool {
        wantsConnection && candidate === peripheral && central?.state == .poweredOn
    }
}

// CoreBluetooth is explicitly configured to deliver every delegate callback on
// the main queue. Identity checks discard callbacks from an ended manager/link.
extension WristbandBluetooth: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central, wantsConnection else { return }
        switch central.state {
        case .poweredOn:
            settingsDenied = false
            unavailableReason = nil
            if peripheral == nil { scan() }
        case .unknown, .resetting:
            if peripheral != nil || isConnected {
                fail("Bluetooth restarted. Reconnect the wristband.")
            } else {
                status = "Preparing Bluetooth…"
            }
        case .poweredOff:
            fail("Bluetooth is off. Turn it on and reconnect the wristband.")
        case .unauthorized:
            settingsDenied = CBManager.authorization == .denied
            fail(settingsDenied ? "Allow Bluetooth for FortWatch in Settings." :
                    "Bluetooth is restricted on this iPhone.")
        case .unsupported:
            fail("This device does not support FortWatch’s Bluetooth connection.")
        @unknown default:
            fail("Bluetooth is unavailable. Try connecting again.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === self.central, wantsConnection, self.peripheral == nil,
              central.state == .poweredOn else { return }
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        status = "Connecting to FortWatch…"
        armConnectionTimeout("The wristband did not respond. Move it closer and reconnect.")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, current(peripheral) else { return }
        status = "Checking the wristband…"
        peripheral.discoverServices([CBUUID(string: WristbandProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, current(peripheral) else { return }
        fail("Could not connect to the wristband. Move it closer and try again.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, current(peripheral) else { return }
        fail("Connection to the wristband was lost. Move it closer and reconnect.")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard current(peripheral), peripheral.state == .connected else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: WristbandProtocol.serviceUUID) }) else {
            fail("The wristband does not provide the expected FortWatch service. Check its firmware.")
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: WristbandProtocol.receiveUUID)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard current(peripheral), peripheral.state == .connected,
              service.uuid == CBUUID(string: WristbandProtocol.serviceUUID) else { return }
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: WristbandProtocol.receiveUUID) }),
              characteristic.properties.contains(.writeWithoutResponse) || characteristic.properties.contains(.write) else {
            fail("The wristband cannot receive alerts. Check its firmware.")
            return
        }
        let wasReady = isConnected
        receiveCharacteristic = characteristic
        connectionTimeout?.cancel()
        connectionTimeout = nil
        connecting = false
        isConnected = true
        unavailableReason = nil
        status = "Wristband connected."
        if !wasReady { onConnect?() }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current(peripheral), characteristic === receiveCharacteristic, responseInFlight else { return }
        responseInFlight = false
        writeTimeout?.cancel()
        writeTimeout = nil
        if error != nil { fail("The wristband rejected the alert. Reconnect.") }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard current(peripheral),
              invalidatedServices.contains(where: { $0.uuid == CBUUID(string: WristbandProtocol.serviceUUID) }) else { return }
        fail("The wristband’s service changed. Reconnect.")
    }
}
