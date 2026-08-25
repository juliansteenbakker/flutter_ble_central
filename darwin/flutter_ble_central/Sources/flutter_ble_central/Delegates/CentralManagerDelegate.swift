//
//  CentralManagerDelegate.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import CoreBluetooth

/**
 A lightweight delegate class for `CBCentralManager` that forwards
 Bluetooth state changes and scan discoveries to the Flutter plugin layer.

 **Responsibilities:**
 - Handle `CBCentralManager` state updates.
 - Handle BLE device discovery events.
 - Forward events to closures defined in `FlutterBleCentralManager`.

 This class acts as a bridge between CoreBluetooth and
 Flutter event handlers, keeping the manager logic clean and testable.
 */
final class CentralManagerDelegate: NSObject, CBCentralManagerDelegate {

    /// Closure type for handling Bluetooth state changes.
    typealias StateChangeHandler = (CBManagerState) -> Void

    /// Closure type for handling peripheral discovery events.
    typealias DiscoveryHandler = (CBPeripheral, AdvertisementData, RSSI) -> Void

    /// Called whenever the Bluetooth state changes.
    private let onStateChange: StateChangeHandler

    /// Called whenever a new peripheral is discovered during scanning.
    private let onDiscovery: DiscoveryHandler

    /// Called when a connection attempt succeeds.
    var onConnect: ((CBPeripheral) -> Void)?

    /// Called when a connection attempt fails.
    var onFailToConnect: ((CBPeripheral, Error?) -> Void)?

    /// Called when a link drops, by request or otherwise.
    var onDisconnect: ((CBPeripheral, Error?) -> Void)?

    /**
     Creates a new delegate with state and discovery callbacks.

     - Parameters:
       - onStateChange: Closure invoked when the central manager's state changes.
       - onDiscovery: Closure invoked when a BLE peripheral is discovered.
     */
    init(
        onStateChange: @escaping StateChangeHandler,
        onDiscovery: @escaping DiscoveryHandler
    ) {
        self.onStateChange = onStateChange
        self.onDiscovery = onDiscovery
    }

    /**
     Called by CoreBluetooth when the central manager's state is updated.

     - Parameter central: The `CBCentralManager` reporting the state change.
     */
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange(central.state)
    }

    /**
     Called by CoreBluetooth when a new peripheral is discovered.

     - Parameters:
       - central: The `CBCentralManager` performing the scan.
       - peripheral: The discovered `CBPeripheral`.
       - advertisementData: A dictionary containing the advertisement data.
       - rssi: The received signal strength indicator (RSSI) in dBm.
     */
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        onDiscovery(peripheral, advertisementData, rssi.intValue)
    }

    /// Called by CoreBluetooth once a connection is up.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnect?(peripheral)
    }

    /// Called by CoreBluetooth when a connection could not be established.
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onFailToConnect?(peripheral, error)
    }

    /// Called by CoreBluetooth when a link drops.
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        onDisconnect?(peripheral, error)
    }
}
