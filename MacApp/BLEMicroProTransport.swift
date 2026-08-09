@preconcurrency import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
final class BLEMicroProTransport: NSObject {
    enum State: String {
        case stopped = "Stopped"
        case bluetoothOff = "Bluetooth is off"
        case scanning = "Looking for Vibe Watch #1"
        case connecting = "Connecting to BLE Micro Pro"
        case ready = "BLE Micro Pro connected"
        case failed = "Connection failed"
    }

    private(set) var state: State = .stopped
    private(set) var detail = "Starting Bluetooth…"
    private(set) var hostHandshakeReceived = false
    private(set) var lastHostMessageAt: Date?

    private static let serviceUUID = CBUUID(string: "83600000-3A2D-4F41-492D-564942455741")
    private static let commandUUID = CBUUID(string: "83600001-3A2D-4F41-492D-564942455741")
    private static let statusUUID = CBUUID(string: "83600002-3A2D-4F41-492D-564942455741")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var status: CBCharacteristic?
    private var rpcBuffer = Data()
    private var onAgentStatus: (([VibeAgentState]) -> Void)?

    var isConnected: Bool { state == .ready && command != nil }

    func start(onAgentStatus: @escaping ([VibeAgentState]) -> Void) {
        guard central == nil else { return }
        self.onAgentStatus = onAgentStatus
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func rescan() {
        guard let central, central.state == .poweredOn else { return }
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        self.peripheral = nil
        command = nil
        status = nil
        hostHandshakeReceived = false
        scan(using: central)
    }

    func send(_ event: VibeEvent) throws {
        guard let peripheral, let command, isConnected else {
            throw BLEMicroProError.notConnected
        }
        let data = event.vendorReport
        guard data.count == VibeEvent.reportLength else {
            throw BLEMicroProError.invalidReport
        }
        peripheral.writeValue(data, for: command, type: .withResponse)
    }

    private func scan(using central: CBCentralManager) {
        state = .scanning
        detail = "Pair Vibe Watch #1 in macOS Bluetooth settings. The bridge will connect automatically."

        let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        if let first = connected.first {
            connect(first, using: central)
            return
        }
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
    }

    private func connect(_ peripheral: CBPeripheral, using central: CBCentralManager) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        detail = "Opening the native HID relay on \(peripheral.name ?? "Vibe Watch #1")…"
        central.connect(peripheral)
    }

    private func consumeHostFrame(_ data: Data) {
        guard data.count == VibeEvent.reportLength,
              data[data.startIndex] == VibeEvent.jsonRPCChannel
        else { return }
        let count = min(Int(data[data.startIndex + 1]), VibeEvent.reportLength - 2)
        rpcBuffer.append(data.dropFirst(2).prefix(count))
        guard let object = try? JSONSerialization.jsonObject(with: rpcBuffer) as? [String: Any] else {
            return
        }
        rpcBuffer.removeAll(keepingCapacity: true)
        hostHandshakeReceived = true
        lastHostMessageAt = .now

        let method = (object["method"] ?? object["m"]) as? String
        let params = object["params"] ?? object["p"]
        guard method == "v.oai.thstatus", let values = params as? [[String: Any]] else { return }
        let agents = values.compactMap { item -> VibeAgentState? in
            guard let id = (item["id"] as? NSNumber)?.intValue else { return nil }
            return VibeAgentState(
                id: id,
                colorHex: (item["c"] as? NSNumber)?.uint32Value ?? 0,
                brightness: (item["b"] as? NSNumber)?.doubleValue ?? 0,
                effect: (item["e"] as? NSNumber)?.intValue ?? 0,
                speed: (item["s"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        onAgentStatus?(agents)
    }
}

@MainActor
extension BLEMicroProTransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            scan(using: central)
        case .poweredOff:
            state = .bluetoothOff
            detail = "Turn on Bluetooth on this Mac."
        case .unauthorized:
            state = .failed
            detail = "Allow Bluetooth access for VibeWatchBridge in System Settings."
        default:
            state = .stopped
            detail = "Waiting for Bluetooth…"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        connect(peripheral, using: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connecting
        detail = "Discovering the 63-byte Codex HID relay…"
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .failed
        detail = error?.localizedDescription ?? "Could not connect to BLE Micro Pro."
        scan(using: central)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        command = nil
        status = nil
        hostHandshakeReceived = false
        scan(using: central)
    }
}

@MainActor
extension BLEMicroProTransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .failed
            detail = error.localizedDescription
            return
        }
        peripheral.services?.forEach { service in
            guard service.uuid == Self.serviceUUID else { return }
            peripheral.discoverCharacteristics([Self.commandUUID, Self.statusUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            state = .failed
            detail = error.localizedDescription
            return
        }
        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == Self.commandUUID { command = characteristic }
            if characteristic.uuid == Self.statusUUID {
                status = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        guard command != nil, status != nil else {
            state = .failed
            detail = "The board is connected, but it is not running Vibe Watch firmware."
            return
        }
        state = .ready
        detail = "Real BLE HID is connected. Waiting for Codex's native handshake."
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == Self.statusUUID, let value = characteristic.value else { return }
        consumeHostFrame(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            state = .failed
            detail = "BLE write failed: \(error.localizedDescription)"
        }
    }
}

private enum BLEMicroProError: LocalizedError {
    case notConnected
    case invalidReport

    var errorDescription: String? {
        switch self {
        case .notConnected: "BLE Micro Pro is not connected. Flash and pair Vibe Watch #1 first."
        case .invalidReport: "The Codex HID report was not exactly 63 bytes."
        }
    }
}
