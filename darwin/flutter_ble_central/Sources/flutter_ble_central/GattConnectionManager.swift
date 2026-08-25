//
//  GattConnectionManager.swift
//  flutter_ble_central
//

import CoreBluetooth

/**
 Connects to peripherals and talks GATT to them, mirroring the Android
 `GattConnectionManager` onto CoreBluetooth.

 A peripheral is addressed by `CBPeripheral.identifier`, since Apple never hands
 out a hardware address. That identifier is what the scan results already report
 as `address`, so the Dart API needs no platform branch, but two things follow
 from it: the value is specific to this app and this device, and it can only be
 resolved for a peripheral this app has seen or has connected to before.

 CoreBluetooth answers every request through a delegate callback rather than a
 return value, so each call parks its completion here and the matching delegate
 method hands it back.
 */
final class GattConnectionManager: NSObject {

    /// What a caller is waiting for. Keyed so the delegate can find it again.
    private struct PendingKey: Hashable {
        let peripheral: UUID
        let kind: String
        let uuid: String
    }

    private typealias Completion = (Result<Any?, Error>) -> Void

    /// Things that only exist on Android, reported rather than failing silently.
    enum Failure: Error, CustomStringConvertible {
        case unknownPeripheral(String)
        case notConnected(String)
        case serviceNotFound(String)
        case characteristicNotFound(String)
        case descriptorNotFound(String)
        case unsupportedOnApple(String)
        case operationFailed(String)

        var code: String {
            switch self {
            case .unknownPeripheral: return "UNKNOWN_PERIPHERAL"
            case .notConnected: return "NOT_CONNECTED"
            case .serviceNotFound: return "SERVICE_NOT_FOUND"
            case .characteristicNotFound: return "CHARACTERISTIC_NOT_FOUND"
            case .descriptorNotFound: return "DESCRIPTOR_NOT_FOUND"
            case .unsupportedOnApple: return "UNSUPPORTED"
            case .operationFailed: return "OPERATION_FAILED"
            }
        }

        var description: String {
            switch self {
            case .unknownPeripheral(let id):
                return "Peripheral \(id) is unknown. Scan for it first, or use an "
                    + "identifier this app has connected to before."
            case .notConnected(let id):
                return "Peripheral \(id) is not connected"
            case .serviceNotFound(let uuid):
                return "Service \(uuid) not found. Call discoverServices first."
            case .characteristicNotFound(let uuid):
                return "Characteristic \(uuid) not found"
            case .descriptorNotFound(let uuid):
                return "Descriptor \(uuid) not found"
            case .unsupportedOnApple(let what):
                return "\(what) is not available on iOS or macOS. CoreBluetooth "
                    + "does not expose it."
            case .operationFailed(let message):
                return message
            }
        }
    }

    private let centralManager: CBCentralManager
    private let connectionStateHandler: ConnectionStateHandler
    private let characteristicValueHandler: CharacteristicValueHandler

    /// Peripherals seen while scanning, so that connect can find one by identifier.
    /// CoreBluetooth drops a peripheral it holds no strong reference to.
    private var knownPeripherals = [UUID: CBPeripheral]()

    /// Peripherals with a link up.
    private var connectedPeripherals = [UUID: CBPeripheral]()

    /// Callbacks waiting on a delegate method.
    private var pending = [PendingKey: Completion]()

    /// Services still to report their characteristics, per peripheral.
    var pendingServiceDiscoveries = [UUID: Int]()

    /// Characteristics still to report their descriptors, per peripheral.
    var pendingDescriptorDiscoveries = [UUID: Int]()

    init(
        centralManager: CBCentralManager,
        connectionStateHandler: ConnectionStateHandler,
        characteristicValueHandler: CharacteristicValueHandler
    ) {
        self.centralManager = centralManager
        self.connectionStateHandler = connectionStateHandler
        self.characteristicValueHandler = characteristicValueHandler
    }

    // MARK: - Discovery bookkeeping

    /// Remembers a peripheral the scan reported, so it can be connected to later.
    func remember(_ peripheral: CBPeripheral) {
        knownPeripherals[peripheral.identifier] = peripheral
    }

    // MARK: - Connecting

    func connect(address: String) throws {
        let peripheral = try resolve(address)
        peripheral.delegate = self
        knownPeripherals[peripheral.identifier] = peripheral
        connectionStateHandler.publish(address: address, state: .connecting)
        centralManager.connect(peripheral)
    }

    func disconnect(address: String) throws {
        let peripheral = try resolve(address)
        connectionStateHandler.publish(address: address, state: .disconnecting)
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// The index of Dart's `GattConnectionState` for this peripheral.
    func connectionState(address: String) -> Int {
        guard let peripheral = knownPeripherals[UUID(uuidString: address) ?? UUID()] else {
            return ConnectionStateHandler.State.disconnected.rawValue
        }
        switch peripheral.state {
        case .disconnected: return ConnectionStateHandler.State.disconnected.rawValue
        case .connecting: return ConnectionStateHandler.State.connecting.rawValue
        case .connected: return ConnectionStateHandler.State.connected.rawValue
        case .disconnecting: return ConnectionStateHandler.State.disconnecting.rawValue
        @unknown default: return ConnectionStateHandler.State.disconnected.rawValue
        }
    }

    // MARK: - Services and characteristics

    func discoverServices(
        address: String,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        do {
            let peripheral = try connected(address)
            park(peripheral, "services", "") { result in
                switch result {
                case .success:
                    completion(.success(self.serviceMaps(of: peripheral)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            peripheral.discoverServices(nil)
        } catch {
            completion(.failure(error))
        }
    }

    func readCharacteristic(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        do {
            let peripheral = try connected(address)
            let characteristic = try find(peripheral, serviceUuid, characteristicUuid)
            park(peripheral, "read", characteristic.uuid.uuidString) { result in
                completion(result.map { ($0 as? Data) ?? Data() })
            }
            peripheral.readValue(for: characteristic)
        } catch {
            completion(.failure(error))
        }
    }

    func writeCharacteristic(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        value: Data,
        withoutResponse: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let peripheral = try connected(address)
            let characteristic = try find(peripheral, serviceUuid, characteristicUuid)
            if withoutResponse {
                // Nothing is acknowledged, so there is nothing to wait for.
                peripheral.writeValue(value, for: characteristic, type: .withoutResponse)
                completion(.success(()))
                return
            }
            park(peripheral, "write", characteristic.uuid.uuidString) { result in
                completion(result.map { _ in () })
            }
            peripheral.writeValue(value, for: characteristic, type: .withResponse)
        } catch {
            completion(.failure(error))
        }
    }

    func setNotify(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        enable: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let peripheral = try connected(address)
            let characteristic = try find(peripheral, serviceUuid, characteristicUuid)
            park(peripheral, "notify", characteristic.uuid.uuidString) { result in
                completion(result.map { _ in () })
            }
            // CoreBluetooth writes the CCCD itself; there is no descriptor to touch.
            peripheral.setNotifyValue(enable, for: characteristic)
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Descriptors

    func readDescriptor(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        do {
            let descriptor = try findDescriptor(
                address, serviceUuid, characteristicUuid, descriptorUuid
            )
            let peripheral = try connected(address)
            park(peripheral, "readDescriptor", descriptor.uuid.uuidString) { result in
                completion(result.map { ($0 as? Data) ?? Data() })
            }
            peripheral.readValue(for: descriptor)
        } catch {
            completion(.failure(error))
        }
    }

    func writeDescriptor(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
        value: Data,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let descriptor = try findDescriptor(
                address, serviceUuid, characteristicUuid, descriptorUuid
            )
            let peripheral = try connected(address)
            park(peripheral, "writeDescriptor", descriptor.uuid.uuidString) { result in
                completion(result.map { _ in () })
            }
            peripheral.writeValue(value, for: descriptor)
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Connection properties

    /**
     The largest payload a write without response can carry, plus the three byte
     ATT header, so that it lines up with the MTU Android reports.

     CoreBluetooth negotiates the MTU itself and offers no way to ask for one, so
     the requested size is ignored and what it settled on is reported instead.
     */
    func mtu(address: String) throws -> Int {
        let peripheral = try connected(address)
        return peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
    }

    func readRssi(
        address: String,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        do {
            let peripheral = try connected(address)
            park(peripheral, "rssi", "") { result in
                completion(result.map { ($0 as? Int) ?? 0 })
            }
            peripheral.readRSSI()
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Connection callbacks, from CentralManagerDelegate

    func handleConnect(_ peripheral: CBPeripheral) {
        connectedPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        connectionStateHandler.publish(
            address: peripheral.identifier.uuidString,
            state: .connected
        )
    }

    func handleDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        failPending(for: peripheral, with: error ?? Failure.notConnected(
            peripheral.identifier.uuidString
        ))
        connectionStateHandler.publish(
            address: peripheral.identifier.uuidString,
            state: .disconnected
        )
    }

    func handleFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        failPending(for: peripheral, with: error ?? Failure.operationFailed(
            "Failed to connect to \(peripheral.identifier.uuidString)"
        ))
        connectionStateHandler.publish(
            address: peripheral.identifier.uuidString,
            state: .disconnected
        )
    }

    /// Drops every connection and forgets what was discovered.
    func cleanup() {
        for peripheral in connectedPeripherals.values {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
        knownPeripherals.removeAll()
        pending.removeAll()
    }

    // MARK: - Lookups

    private func resolve(_ address: String) throws -> CBPeripheral {
        guard let identifier = UUID(uuidString: address) else {
            throw Failure.unknownPeripheral(address)
        }
        if let peripheral = knownPeripherals[identifier] {
            return peripheral
        }
        // A peripheral this app connected to before can be retrieved without a
        // scan; one it has never seen cannot be resolved at all.
        guard let peripheral = centralManager
            .retrievePeripherals(withIdentifiers: [identifier]).first else {
            throw Failure.unknownPeripheral(address)
        }
        knownPeripherals[identifier] = peripheral
        return peripheral
    }

    private func connected(_ address: String) throws -> CBPeripheral {
        let peripheral = try resolve(address)
        guard peripheral.state == .connected else {
            throw Failure.notConnected(address)
        }
        return peripheral
    }

    private func find(
        _ peripheral: CBPeripheral,
        _ serviceUuid: String,
        _ characteristicUuid: String
    ) throws -> CBCharacteristic {
        guard let service = peripheral.services?.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(serviceUuid) == .orderedSame
        }) else {
            throw Failure.serviceNotFound(serviceUuid)
        }
        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(characteristicUuid) == .orderedSame
        }) else {
            throw Failure.characteristicNotFound(characteristicUuid)
        }
        return characteristic
    }

    private func findDescriptor(
        _ address: String,
        _ serviceUuid: String,
        _ characteristicUuid: String,
        _ descriptorUuid: String
    ) throws -> CBDescriptor {
        let peripheral = try connected(address)
        let characteristic = try find(peripheral, serviceUuid, characteristicUuid)
        guard let descriptor = characteristic.descriptors?.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(descriptorUuid) == .orderedSame
        }) else {
            throw Failure.descriptorNotFound(descriptorUuid)
        }
        return descriptor
    }

    /// The shape Dart's `GattService.fromJson` expects, same as Android sends.
    private func serviceMaps(of peripheral: CBPeripheral) -> [[String: Any]] {
        return (peripheral.services ?? []).map { service in
            [
                "uuid": service.uuid.uuidString.lowercased(),
                "isPrimary": service.isPrimary,
                "characteristics": (service.characteristics ?? []).map { characteristic in
                    [
                        "uuid": characteristic.uuid.uuidString.lowercased(),
                        "serviceUuid": service.uuid.uuidString.lowercased(),
                        "properties": propertyMap(characteristic.properties),
                        "descriptors": (characteristic.descriptors ?? []).map { descriptor in
                            [
                                "uuid": descriptor.uuid.uuidString.lowercased(),
                                "characteristicUuid":
                                    characteristic.uuid.uuidString.lowercased(),
                            ] as [String: Any]
                        },
                    ] as [String: Any]
                },
            ] as [String: Any]
        }
    }

    private func propertyMap(_ properties: CBCharacteristicProperties) -> [String: Bool] {
        return [
            "broadcast": properties.contains(.broadcast),
            "read": properties.contains(.read),
            "writeWithoutResponse": properties.contains(.writeWithoutResponse),
            "write": properties.contains(.write),
            "notify": properties.contains(.notify),
            "indicate": properties.contains(.indicate),
            "authenticatedSignedWrites": properties.contains(.authenticatedSignedWrites),
            "extendedProperties": properties.contains(.extendedProperties),
        ]
    }

    // MARK: - Pending callbacks

    private func park(
        _ peripheral: CBPeripheral,
        _ kind: String,
        _ uuid: String,
        _ completion: @escaping Completion
    ) {
        let key = PendingKey(
            peripheral: peripheral.identifier,
            kind: kind,
            uuid: uuid.lowercased()
        )
        // A second request for the same thing replaces the first, which would
        // otherwise never be answered.
        pending[key]?(.failure(Failure.operationFailed("Superseded by a newer request")))
        pending[key] = completion
    }

    func settle(
        _ peripheral: CBPeripheral,
        _ kind: String,
        _ uuid: String,
        _ result: Result<Any?, Error>
    ) {
        let key = PendingKey(
            peripheral: peripheral.identifier,
            kind: kind,
            uuid: uuid.lowercased()
        )
        guard let completion = pending.removeValue(forKey: key) else { return }
        completion(result)
    }

    /// Whether a caller is waiting on this exact callback.
    func hasPending(_ peripheral: CBPeripheral, _ kind: String, _ uuid: String) -> Bool {
        let key = PendingKey(
            peripheral: peripheral.identifier,
            kind: kind,
            uuid: uuid.lowercased()
        )
        return pending[key] != nil
    }

    /// Reports a notification to Dart.
    func publishValue(
        _ peripheral: CBPeripheral,
        _ characteristic: CBCharacteristic,
        _ value: Data
    ) {
        characteristicValueHandler.publish(
            address: peripheral.identifier.uuidString,
            serviceUuid: characteristic.service?.uuid.uuidString.lowercased() ?? "",
            characteristicUuid: characteristic.uuid.uuidString.lowercased(),
            value: value
        )
    }

    /// Counts one service off the discovery, and answers the caller once every
    /// service and descriptor has reported in.
    func finishService(_ peripheral: CBPeripheral) {
        guard let services = pendingServiceDiscoveries[peripheral.identifier] else {
            return
        }
        let remainingDescriptors = pendingDescriptorDiscoveries[peripheral.identifier] ?? 0
        let remainingServices = services - 1
        pendingServiceDiscoveries[peripheral.identifier] = remainingServices

        if remainingServices <= 0 && remainingDescriptors <= 0 {
            pendingServiceDiscoveries.removeValue(forKey: peripheral.identifier)
            pendingDescriptorDiscoveries.removeValue(forKey: peripheral.identifier)
            settle(peripheral, "services", "", .success(nil))
        }
    }

    private func failPending(for peripheral: CBPeripheral, with error: Error) {
        for key in pending.keys where key.peripheral == peripheral.identifier {
            pending.removeValue(forKey: key)?(.failure(error))
        }
    }
}
