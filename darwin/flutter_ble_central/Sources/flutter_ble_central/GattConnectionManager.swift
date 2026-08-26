//
//  GattConnectionManager.swift
//  flutter_ble_central
//

import Foundation
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import CoreBluetooth

/// Mirrors the Dart `GattConnectionState`.
enum GattConnectionState: Int {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case disconnecting = 3
}

/**
 Serves the GATT client half on iOS and macOS: holds a connection per
 peripheral, keeps what it serves, and answers each Dart call once Core
 Bluetooth has finished the operation rather than when the request went in.

 Every member is touched on `queue`, the same serial queue Core Bluetooth
 delivers its callbacks on, so the delegate callbacks and the calls coming down
 from Dart cannot race each other. Only the replies and the stream publishes hop
 to the platform thread, as Flutter channels require.
 */
final class GattConnectionManager: NSObject {

    /// Identifies one characteristic on one peripheral, for the operations that
    /// are outstanding against it.
    private struct OperationKey: Hashable {
        let peripheral: UUID
        let service: String
        let characteristic: String
        let descriptor: String

        init(_ peripheral: UUID, _ service: String, _ characteristic: String,
             _ descriptor: String = "") {
            self.peripheral = peripheral
            self.service = service
            self.characteristic = characteristic
            self.descriptor = descriptor
        }
    }

    /// What is known about one peripheral this plugin is holding open.
    private final class Connection {
        let peripheral: CBPeripheral
        /// Filled in by discoverServices; a read or a write finds what it needs
        /// here rather than going back to the peripheral for it.
        var services: [CBService] = []
        /// Callbacks still outstanding on the discovery in progress.
        var pendingDiscovery = 0
        var discoveryResult: FlutterResult?
        /// Cancels a connection attempt that never lands.
        var timeout: DispatchWorkItem?
        /// The last state published, so only changes are sent.
        var state: GattConnectionState = .disconnected

        init(peripheral: CBPeripheral) {
            self.peripheral = peripheral
        }
    }

    private let centralManager: CBCentralManager
    private let queue: DispatchQueue

    private let connectionStateHandler: ConnectionEventHandler
    private let characteristicValueHandler: ConnectionEventHandler

    /// Held so that Core Bluetooth does not let the peripherals go: it does not
    /// retain one that is being connected to, and the connection is dropped
    /// silently if nothing else does.
    private var connections: [UUID: Connection] = [:]

    private var readResults: [OperationKey: FlutterResult] = [:]
    private var writeResults: [OperationKey: FlutterResult] = [:]
    private var notifyResults: [OperationKey: FlutterResult] = [:]
    private var descriptorReadResults: [OperationKey: FlutterResult] = [:]
    private var descriptorWriteResults: [OperationKey: FlutterResult] = [:]
    private var rssiResults: [UUID: FlutterResult] = [:]

    init(
        centralManager: CBCentralManager,
        queue: DispatchQueue,
        connectionStateHandler: ConnectionEventHandler,
        characteristicValueHandler: ConnectionEventHandler
    ) {
        self.centralManager = centralManager
        self.queue = queue
        self.connectionStateHandler = connectionStateHandler
        self.characteristicValueHandler = characteristicValueHandler
        super.init()
    }

    // MARK: - Helpers

    /// The canonical lowercase 128 bit form, so a uuid matches what the Android
    /// implementation reports and round-trips against the one Dart sent back.
    static func fullUuid(_ uuid: CBUUID) -> String {
        let text = uuid.uuidString.lowercased()
        switch text.count {
        case 4:
            return "0000\(text)-0000-1000-8000-00805f9b34fb"
        case 8:
            return "\(text)-0000-1000-8000-00805f9b34fb"
        default:
            return text
        }
    }

    /// Accepts the 16 bit ("A1B2"), 32 bit ("A1B2C3D4") and 128 bit forms, with
    /// or without dashes, the way the Android and Windows sides do.
    ///
    /// `CBUUID(string:)` raises an Objective-C exception on anything it does not
    /// recognise, and that cannot be caught from Swift: it takes the app down
    /// rather than reaching Dart. So the shape is checked, and expanded onto the
    /// Bluetooth Base UUID, before it is handed over.
    ///
    /// - Parameter value: The uuid Dart sent.
    /// - Returns: The parsed uuid, or nil when it is not one.
    static func parseUuid(_ value: String) -> CBUUID? {
        let hex = value.replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        let full: String
        switch hex.count {
        case 4:
            full = "0000\(hex)-0000-1000-8000-00805f9b34fb"
        case 8:
            full = "\(hex)-0000-1000-8000-00805f9b34fb"
        case 32:
            let characters = Array(hex)
            full = String(characters[0..<8]) + "-"
                + String(characters[8..<12]) + "-"
                + String(characters[12..<16]) + "-"
                + String(characters[16..<20]) + "-"
                + String(characters[20..<32])
        default:
            return nil
        }
        return CBUUID(string: full)
    }

    /// Replies to Dart, which has to happen on the platform thread.
    private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
        DispatchQueue.main.async { result(value) }
    }

    private func fail(_ result: @escaping FlutterResult, _ code: String,
                      _ message: String) {
        DispatchQueue.main.async {
            result(FlutterError(code: code, message: message, details: nil))
        }
    }

    /// The peripheral behind an address Dart sent, whether it is one this plugin
    /// is already holding or one the system merely knows about.
    private func peripheral(for address: String) -> CBPeripheral? {
        guard let identifier = UUID(uuidString: address) else { return nil }
        if let connection = connections[identifier] { return connection.peripheral }
        return centralManager.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    /// Looks up a characteristic that discoverServices already found.
    private func characteristic(
        _ connection: Connection, _ serviceUuid: String, _ characteristicUuid: String
    ) -> CBCharacteristic? {
        guard let service = connection.services.first(
            where: { GattConnectionManager.fullUuid($0.uuid) == serviceUuid }
        ) else { return nil }
        return service.characteristics?.first(
            where: { GattConnectionManager.fullUuid($0.uuid) == characteristicUuid }
        )
    }

    private func publishState(_ connection: Connection, _ state: GattConnectionState) {
        guard connection.state != state else { return }
        connection.state = state
        connectionStateHandler.publish([
            "address": connection.peripheral.identifier.uuidString,
            "state": state.rawValue,
        ])
    }

    /// Answers everything still outstanding against a peripheral, so that a
    /// disconnect never leaves a Dart future hanging.
    private func failOutstanding(_ identifier: UUID, _ message: String) {
        // The keys are taken first: each result is removed from the dictionary it
        // came out of, which is not something to do while iterating it.
        for key in readResults.keys.filter({ $0.peripheral == identifier }) {
            if let result = readResults.removeValue(forKey: key) {
                fail(result, "READ_ERROR", message)
            }
        }
        for key in writeResults.keys.filter({ $0.peripheral == identifier }) {
            if let result = writeResults.removeValue(forKey: key) {
                fail(result, "WRITE_ERROR", message)
            }
        }
        for key in notifyResults.keys.filter({ $0.peripheral == identifier }) {
            if let result = notifyResults.removeValue(forKey: key) {
                fail(result, "NOTIFICATION_ERROR", message)
            }
        }
        for key in descriptorReadResults.keys.filter({ $0.peripheral == identifier }) {
            if let result = descriptorReadResults.removeValue(forKey: key) {
                fail(result, "READ_DESCRIPTOR_ERROR", message)
            }
        }
        for key in descriptorWriteResults.keys.filter({ $0.peripheral == identifier }) {
            if let result = descriptorWriteResults.removeValue(forKey: key) {
                fail(result, "WRITE_DESCRIPTOR_ERROR", message)
            }
        }

        if let result = rssiResults.removeValue(forKey: identifier) {
            fail(result, "RSSI_ERROR", message)
        }
        if let connection = connections[identifier],
           let result = connection.discoveryResult {
            connection.discoveryResult = nil
            connection.pendingDiscovery = 0
            fail(result, "SERVICE_DISCOVERY_ERROR", message)
        }
    }

    // MARK: - Connection

    func connect(address: String, timeout: Int, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }

            guard let peripheral = self.peripheral(for: address) else {
                self.fail(result, "CONNECTION_ERROR",
                          "No peripheral with that identifier is known; scan for it first")
                return
            }
            let identifier = peripheral.identifier

            if let existing = self.connections[identifier],
               existing.peripheral.state == .connected {
                self.fail(result, "CONNECTION_ERROR", "Already connected to device")
                return
            }

            let connection = Connection(peripheral: peripheral)
            peripheral.delegate = self
            self.connections[identifier] = connection

            // Core Bluetooth never gives up on its own, so the timeout Dart asked
            // for is kept here.
            if timeout > 0 {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    guard let current = self.connections[identifier],
                          current.peripheral.state != .connected else { return }
                    self.centralManager.cancelPeripheralConnection(current.peripheral)
                    self.publishState(current, .disconnected)
                    self.connections.removeValue(forKey: identifier)
                    self.failOutstanding(identifier, "The connection timed out")
                }
                connection.timeout = work
                self.queue.asyncAfter(
                    deadline: .now() + .milliseconds(timeout), execute: work
                )
            }

            self.centralManager.connect(peripheral, options: nil)
            self.publishState(connection, .connecting)

            // Answered as soon as the request is in, the way the Android side does
            // it; the outcome arrives on the connection state stream.
            self.reply(result, nil)
        }
    }

    func disconnect(address: String, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier] else {
                self.fail(result, "CONNECTION_ERROR", "Device not connected")
                return
            }
            connection.timeout?.cancel()
            self.publishState(connection, .disconnecting)
            self.centralManager.cancelPeripheralConnection(connection.peripheral)
            self.reply(result, nil)
        }
    }

    func connectionState(address: String, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier] else {
                self.reply(result, GattConnectionState.disconnected.rawValue)
                return
            }
            let state: GattConnectionState
            switch connection.peripheral.state {
            case .connected: state = .connected
            case .connecting: state = .connecting
            case .disconnecting: state = .disconnecting
            default: state = .disconnected
            }
            self.reply(result, state.rawValue)
        }
    }

    /// Reports the MTU the link negotiated. Core Bluetooth offers no way to ask
    /// for one, so the size Dart requested is ignored.
    func mtu(address: String, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "MTU_ERROR", "Device not connected")
                return
            }
            // Core Bluetooth reports the largest payload a write can carry; the
            // ATT MTU is three bytes larger, which is what Dart reports.
            let payload = connection.peripheral.maximumWriteValueLength(for: .withoutResponse)
            self.reply(result, payload + 3)
        }
    }

    func readRssi(address: String, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "RSSI_ERROR", "Device not connected")
                return
            }
            self.rssiResults[identifier] = result
            connection.peripheral.readRSSI()
        }
    }

    // MARK: - Discovery

    func discoverServices(address: String, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "SERVICE_DISCOVERY_ERROR", "Device not connected")
                return
            }
            if connection.discoveryResult != nil {
                self.fail(result, "SERVICE_DISCOVERY_ERROR",
                          "A discovery is already running for this device")
                return
            }
            connection.discoveryResult = result
            connection.pendingDiscovery = 0
            connection.services = []
            connection.peripheral.discoverServices(nil)
        }
    }

    /// Called on `queue` once no discovery callback is outstanding.
    private func finishDiscovery(_ connection: Connection) {
        guard let result = connection.discoveryResult else { return }
        connection.discoveryResult = nil

        let services: [[String: Any]] = connection.services.map { service in
            let serviceUuid = GattConnectionManager.fullUuid(service.uuid)
            let characteristics: [[String: Any]] =
                (service.characteristics ?? []).map { characteristic in
                    let characteristicUuid =
                        GattConnectionManager.fullUuid(characteristic.uuid)
                    let properties = characteristic.properties
                    let descriptors: [[String: Any]] =
                        (characteristic.descriptors ?? []).map { descriptor in
                            [
                                "uuid": GattConnectionManager.fullUuid(descriptor.uuid),
                                "characteristicUuid": characteristicUuid,
                                "serviceUuid": serviceUuid,
                            ]
                        }
                    return [
                        "uuid": characteristicUuid,
                        "serviceUuid": serviceUuid,
                        "properties": [
                            "broadcast": properties.contains(.broadcast),
                            "read": properties.contains(.read),
                            "writeWithoutResponse":
                                properties.contains(.writeWithoutResponse),
                            "write": properties.contains(.write),
                            "notify": properties.contains(.notify),
                            "indicate": properties.contains(.indicate),
                            "authenticatedSignedWrites":
                                properties.contains(.authenticatedSignedWrites),
                            "extendedProperties":
                                properties.contains(.extendedProperties),
                        ],
                        "descriptors": descriptors,
                    ]
                }
            return [
                "uuid": serviceUuid,
                "isPrimary": service.isPrimary,
                "characteristics": characteristics,
            ]
        }

        reply(result, services)
    }

    // MARK: - Characteristics

    func readCharacteristic(
        address: String, serviceUuid: String, characteristicUuid: String,
        result: @escaping FlutterResult
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "READ_ERROR", "Device not connected")
                return
            }
            guard let characteristic = self.characteristic(
                connection, serviceUuid, characteristicUuid
            ) else {
                self.fail(result, "READ_ERROR",
                          "Characteristic not found; call discoverServices before reading")
                return
            }
            guard characteristic.properties.contains(.read) else {
                self.fail(result, "READ_ERROR",
                          "Characteristic does not support read")
                return
            }
            let key = OperationKey(identifier, serviceUuid, characteristicUuid)
            self.readResults[key] = result
            connection.peripheral.readValue(for: characteristic)
        }
    }

    func writeCharacteristic(
        address: String, serviceUuid: String, characteristicUuid: String,
        value: Data, withoutResponse: Bool, result: @escaping FlutterResult
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "WRITE_ERROR", "Device not connected")
                return
            }
            guard let characteristic = self.characteristic(
                connection, serviceUuid, characteristicUuid
            ) else {
                self.fail(result, "WRITE_ERROR",
                          "Characteristic not found; call discoverServices before writing")
                return
            }
            let required: CBCharacteristicProperties =
                withoutResponse ? .writeWithoutResponse : .write
            guard characteristic.properties.contains(required) else {
                self.fail(result, "WRITE_ERROR", withoutResponse
                    ? "Characteristic does not support write without response"
                    : "Characteristic does not support write")
                return
            }

            if withoutResponse {
                // Core Bluetooth reports nothing back for one of these, so there
                // is nothing to wait for.
                connection.peripheral.writeValue(
                    value, for: characteristic, type: .withoutResponse
                )
                self.reply(result, nil)
                return
            }

            let key = OperationKey(identifier, serviceUuid, characteristicUuid)
            self.writeResults[key] = result
            connection.peripheral.writeValue(
                value, for: characteristic, type: .withResponse
            )
        }
    }

    func setCharacteristicNotification(
        address: String, serviceUuid: String, characteristicUuid: String,
        enable: Bool, result: @escaping FlutterResult
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "NOTIFICATION_ERROR", "Device not connected")
                return
            }
            guard let characteristic = self.characteristic(
                connection, serviceUuid, characteristicUuid
            ) else {
                self.fail(result, "NOTIFICATION_ERROR",
                          "Characteristic not found; call discoverServices first")
                return
            }
            if enable, !characteristic.properties.contains(.notify),
               !characteristic.properties.contains(.indicate) {
                self.fail(result, "NOTIFICATION_ERROR",
                          "Characteristic supports neither notify nor indicate")
                return
            }
            let key = OperationKey(identifier, serviceUuid, characteristicUuid)
            self.notifyResults[key] = result
            connection.peripheral.setNotifyValue(enable, for: characteristic)
        }
    }

    // MARK: - Descriptors

    func readDescriptor(
        address: String, serviceUuid: String, characteristicUuid: String,
        descriptorUuid: String, result: @escaping FlutterResult
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "READ_DESCRIPTOR_ERROR", "Device not connected")
                return
            }
            guard let characteristic = self.characteristic(
                    connection, serviceUuid, characteristicUuid),
                  let descriptor = characteristic.descriptors?.first(where: {
                      GattConnectionManager.fullUuid($0.uuid) == descriptorUuid
                  }) else {
                self.fail(result, "READ_DESCRIPTOR_ERROR", "Descriptor not found")
                return
            }
            let key = OperationKey(
                identifier, serviceUuid, characteristicUuid, descriptorUuid
            )
            self.descriptorReadResults[key] = result
            connection.peripheral.readValue(for: descriptor)
        }
    }

    func writeDescriptor(
        address: String, serviceUuid: String, characteristicUuid: String,
        descriptorUuid: String, value: Data, result: @escaping FlutterResult
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let identifier = UUID(uuidString: address),
                  let connection = self.connections[identifier],
                  connection.peripheral.state == .connected else {
                self.fail(result, "WRITE_DESCRIPTOR_ERROR", "Device not connected")
                return
            }
            guard let characteristic = self.characteristic(
                    connection, serviceUuid, characteristicUuid),
                  let descriptor = characteristic.descriptors?.first(where: {
                      GattConnectionManager.fullUuid($0.uuid) == descriptorUuid
                  }) else {
                self.fail(result, "WRITE_DESCRIPTOR_ERROR", "Descriptor not found")
                return
            }
            let key = OperationKey(
                identifier, serviceUuid, characteristicUuid, descriptorUuid
            )
            self.descriptorWriteResults[key] = result
            connection.peripheral.writeValue(value, for: descriptor)
        }
    }

    // MARK: - Central manager callbacks

    /// Called from the central manager delegate, already on `queue`.
    func handleDidConnect(_ peripheral: CBPeripheral) {
        guard let connection = connections[peripheral.identifier] else { return }
        connection.timeout?.cancel()
        connection.timeout = nil
        publishState(connection, .connected)
    }

    func handleDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        guard let connection = connections[peripheral.identifier] else { return }
        connection.timeout?.cancel()
        publishState(connection, .disconnected)
        connections.removeValue(forKey: peripheral.identifier)
        failOutstanding(peripheral.identifier,
                        error?.localizedDescription ?? "The connection failed")
    }

    func handleDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        guard let connection = connections[peripheral.identifier] else { return }
        connection.timeout?.cancel()
        publishState(connection, .disconnected)
        connections.removeValue(forKey: peripheral.identifier)
        failOutstanding(peripheral.identifier,
                        error?.localizedDescription ?? "The peripheral disconnected")
    }

    // Nothing tears the connections down by hand. Unlike WinRT, Core Bluetooth
    // drops what a central manager holds when the manager itself goes away, and
    // this one lives as long as the plugin does.
}

// MARK: - CBPeripheralDelegate

extension GattConnectionManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let connection = connections[peripheral.identifier],
              connection.discoveryResult != nil else { return }

        if let error = error {
            let result = connection.discoveryResult
            connection.discoveryResult = nil
            if let result = result {
                fail(result, "SERVICE_DISCOVERY_ERROR", error.localizedDescription)
            }
            return
        }

        connection.services = peripheral.services ?? []
        connection.pendingDiscovery = connection.services.count
        if connection.pendingDiscovery == 0 {
            finishDiscovery(connection)
            return
        }
        for service in connection.services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let connection = connections[peripheral.identifier],
              connection.discoveryResult != nil else { return }

        connection.pendingDiscovery -= 1

        // A service that refuses to be read is reported without its
        // characteristics rather than failing the whole discovery.
        if error == nil {
            let characteristics = service.characteristics ?? []
            connection.pendingDiscovery += characteristics.count
            for characteristic in characteristics {
                peripheral.discoverDescriptors(for: characteristic)
            }
        }

        if connection.pendingDiscovery == 0 {
            finishDiscovery(connection)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let connection = connections[peripheral.identifier],
              connection.discoveryResult != nil else { return }

        connection.pendingDiscovery -= 1
        if connection.pendingDiscovery == 0 {
            finishDiscovery(connection)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let service = characteristic.service else { return }
        let serviceUuid = GattConnectionManager.fullUuid(service.uuid)
        let characteristicUuid = GattConnectionManager.fullUuid(characteristic.uuid)
        let key = OperationKey(peripheral.identifier, serviceUuid, characteristicUuid)

        // This one callback carries both a read that was asked for and a
        // notification that arrived on its own, so a pending read wins.
        if let result = readResults.removeValue(forKey: key) {
            if let error = error {
                fail(result, "READ_ERROR", error.localizedDescription)
            } else {
                reply(result, [UInt8](characteristic.value ?? Data()))
            }
            return
        }

        guard error == nil, let value = characteristic.value else { return }
        characteristicValueHandler.publish([
            "address": peripheral.identifier.uuidString,
            "serviceUuid": serviceUuid,
            "characteristicUuid": characteristicUuid,
            "value": FlutterStandardTypedData(bytes: value),
        ])
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let service = characteristic.service else { return }
        let key = OperationKey(
            peripheral.identifier,
            GattConnectionManager.fullUuid(service.uuid),
            GattConnectionManager.fullUuid(characteristic.uuid)
        )
        guard let result = writeResults.removeValue(forKey: key) else { return }
        if let error = error {
            fail(result, "WRITE_ERROR", error.localizedDescription)
        } else {
            reply(result, nil)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let service = characteristic.service else { return }
        let key = OperationKey(
            peripheral.identifier,
            GattConnectionManager.fullUuid(service.uuid),
            GattConnectionManager.fullUuid(characteristic.uuid)
        )
        guard let result = notifyResults.removeValue(forKey: key) else { return }
        if let error = error {
            fail(result, "NOTIFICATION_ERROR", error.localizedDescription)
        } else {
            reply(result, nil)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor descriptor: CBDescriptor,
        error: Error?
    ) {
        guard let characteristic = descriptor.characteristic,
              let service = characteristic.service else { return }
        let key = OperationKey(
            peripheral.identifier,
            GattConnectionManager.fullUuid(service.uuid),
            GattConnectionManager.fullUuid(characteristic.uuid),
            GattConnectionManager.fullUuid(descriptor.uuid)
        )
        guard let result = descriptorReadResults.removeValue(forKey: key) else { return }
        if let error = error {
            fail(result, "READ_DESCRIPTOR_ERROR", error.localizedDescription)
            return
        }
        reply(result, [UInt8](GattConnectionManager.descriptorBytes(descriptor)))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor descriptor: CBDescriptor,
        error: Error?
    ) {
        guard let characteristic = descriptor.characteristic,
              let service = characteristic.service else { return }
        let key = OperationKey(
            peripheral.identifier,
            GattConnectionManager.fullUuid(service.uuid),
            GattConnectionManager.fullUuid(characteristic.uuid),
            GattConnectionManager.fullUuid(descriptor.uuid)
        )
        guard let result = descriptorWriteResults.removeValue(forKey: key) else { return }
        if let error = error {
            fail(result, "WRITE_DESCRIPTOR_ERROR", error.localizedDescription)
        } else {
            reply(result, nil)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didReadRSSI RSSI: NSNumber,
        error: Error?
    ) {
        guard let result = rssiResults.removeValue(forKey: peripheral.identifier)
        else { return }
        if let error = error {
            fail(result, "RSSI_ERROR", error.localizedDescription)
        } else {
            reply(result, RSSI.intValue)
        }
    }

    /// A descriptor's value is typed by its uuid rather than always being bytes,
    /// so the ones Core Bluetooth hands back as a number or a string are put back
    /// into the bytes the Android side reports.
    private static func descriptorBytes(_ descriptor: CBDescriptor) -> Data {
        switch descriptor.value {
        case let data as Data:
            return data
        case let number as NSNumber:
            var value = number.uint16Value
            return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
        case let text as String:
            return Data(text.utf8)
        default:
            return Data()
        }
    }
}
