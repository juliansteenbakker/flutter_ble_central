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

    /// Closure type for the connection events the GATT client half follows.
    typealias ConnectionHandler = (CBPeripheral, Error?) -> Void

    /// Closure type for the peripherals Core Bluetooth hands back after it
    /// relaunched the app into the background.
    typealias RestoreHandler = ([CBPeripheral]) -> Void

    /// Set once the GATT connection manager exists. It cannot be handed in here,
    /// since it needs the central manager that this delegate is built with.
    var onConnect: ConnectionHandler?
    var onConnectFailed: ConnectionHandler?
    var onDisconnect: ConnectionHandler?
    var onRestore: RestoreHandler?

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
     Called by CoreBluetooth when it has relaunched the app into the background and
     is handing back the peripherals it kept connected in the meantime.

     This arrives before `centralManagerDidUpdateState`, and before anything Dart
     asks for, which is what makes it the place to take the connections back.

     - Parameters:
       - central: The `CBCentralManager` being restored.
       - dict: The state Core Bluetooth kept, keyed by its restoration keys.
     */
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        onRestore?(peripherals)
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

    /**
     Called by CoreBluetooth once a connection is established.

     - Parameters:
       - central: The `CBCentralManager` that made the connection.
       - peripheral: The peripheral now connected.
     */
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        onConnect?(peripheral, nil)
    }

    /**
     Called by CoreBluetooth when a connection could not be established.

     - Parameters:
       - central: The `CBCentralManager` that tried.
       - peripheral: The peripheral it could not reach.
       - error: Why it failed, when the system says.
     */
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onConnectFailed?(peripheral, error)
    }

    /**
     Called by CoreBluetooth when a connection ends, whether this app asked for
     it or the peripheral went away.

     - Parameters:
       - central: The `CBCentralManager` reporting it.
       - peripheral: The peripheral that is no longer connected.
       - error: Set when the link dropped rather than being closed.
     */
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        onDisconnect?(peripheral, error)
    }
}
