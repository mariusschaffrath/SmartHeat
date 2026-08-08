import Foundation
@preconcurrency import CoreBluetooth
import Combine

@MainActor
class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isBluetoothEnabled = false
    @Published var connectedPeripheral: CBPeripheral?
    @Published var discoveredPeripherals = [CBPeripheral]()
    @Published var lastReceivedData: String = ""
    
    private var centralManager: CBCentralManager!
    private var targetCharacteristic: CBCharacteristic?
    
    // UUIDs from APK Analysis
    nonisolated let serviceUUID = CBUUID(string: "ABE72BD1-0257-B362-CA14-753A4D74528A")
    nonisolated let characteristicUUID = CBUUID(string: "021A9004-0382-4AEA-BFF4-6B3F1C5ADFB4")
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    func sendCommand(_ command: StoveCommand) {
        guard let peripheral = connectedPeripheral, let characteristic = targetCharacteristic else { return }
        if let data = command.rawString.data(using: .utf8) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            isBluetoothEnabled = (state == .poweredOn)
            if state == .poweredOn {
                startScanning()
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            if !discoveredPeripherals.contains(peripheral) {
                discoveredPeripherals.append(peripheral)
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedPeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([serviceUUID])
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                Task { @MainActor in
                    self.targetCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value, let string = String(data: data, encoding: .utf8) {
            Task { @MainActor in
                self.lastReceivedData = string
            }
        }
    }
}
