//
//  PeripheralDelegate.swift
//  flutter_ble_central
//

import CoreBluetooth

/**
 The CoreBluetooth side of `GattConnectionManager`.

 Every request parked a completion; these callbacks are where they are handed
 back. A notification arrives on the same callback as a read, told apart by
 whether anything was waiting for it.
 */
extension GattConnectionManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            settle(peripheral, "services", "", .failure(error!))
            return
        }

        // Dart expects the characteristics with the services, so the discovery is
        // only finished once every service has reported its own.
        let services = peripheral.services ?? []
        if services.isEmpty {
            settle(peripheral, "services", "", .success(nil))
            return
        }
        pendingServiceDiscoveries[peripheral.identifier] = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        // Descriptors are a third round trip. Ask for them, then count this
        // service as done once they arrive, or immediately when there are none.
        let characteristics = service.characteristics ?? []
        if error == nil, !characteristics.isEmpty {
            pendingDescriptorDiscoveries[peripheral.identifier] =
                (pendingDescriptorDiscoveries[peripheral.identifier] ?? 0)
                + characteristics.count
            for characteristic in characteristics {
                peripheral.discoverDescriptors(for: characteristic)
            }
        }
        finishService(peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let remaining = (pendingDescriptorDiscoveries[peripheral.identifier] ?? 1) - 1
        pendingDescriptorDiscoveries[peripheral.identifier] = remaining
        finishService(peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString
        if let error = error {
            settle(peripheral, "read", uuid, .failure(error))
            return
        }

        let value = characteristic.value ?? Data()
        if hasPending(peripheral, "read", uuid) {
            settle(peripheral, "read", uuid, .success(value))
            return
        }

        // Nothing was waiting, so this is a notification rather than a read.
        publishValue(peripheral, characteristic, value)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString
        settle(
            peripheral, "write", uuid,
            error.map { Result<Any?, Error>.failure($0) } ?? .success(nil)
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid.uuidString
        settle(
            peripheral, "notify", uuid,
            error.map { Result<Any?, Error>.failure($0) } ?? .success(nil)
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor descriptor: CBDescriptor,
        error: Error?
    ) {
        let uuid = descriptor.uuid.uuidString
        if let error = error {
            settle(peripheral, "readDescriptor", uuid, .failure(error))
            return
        }
        settle(peripheral, "readDescriptor", uuid, .success(Self.data(of: descriptor)))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor descriptor: CBDescriptor,
        error: Error?
    ) {
        let uuid = descriptor.uuid.uuidString
        settle(
            peripheral, "writeDescriptor", uuid,
            error.map { Result<Any?, Error>.failure($0) } ?? .success(nil)
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didReadRSSI RSSI: NSNumber,
        error: Error?
    ) {
        settle(
            peripheral, "rssi", "",
            error.map { Result<Any?, Error>.failure($0) } ?? .success(RSSI.intValue)
        )
    }

    /**
     A descriptor's value is typed rather than raw, so it is rendered back into
     the bytes Dart expects.
     */
    private static func data(of descriptor: CBDescriptor) -> Data {
        switch descriptor.value {
        case let value as Data:
            return value
        case let value as NSNumber:
            var raw = value.uint16Value.littleEndian
            return Data(bytes: &raw, count: MemoryLayout<UInt16>.size)
        case let value as String:
            return Data(value.utf8)
        default:
            return Data()
        }
    }
}
