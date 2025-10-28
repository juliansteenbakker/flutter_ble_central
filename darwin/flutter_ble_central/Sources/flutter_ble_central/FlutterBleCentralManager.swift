//
//  FlutterBleCentralManager.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import CoreBluetooth

typealias RSSI = Int
typealias PeripheralID = UUID
typealias ServiceID = CBUUID
typealias CharacteristicID = CBUUID
typealias ServiceData = [ServiceID: Data]
typealias AdvertisementData = [String: Any]

/**
 `FlutterBleCentralManager` is a wrapper around `CBCentralManager`
 responsible for managing Bluetooth scanning and permission state
 for the Flutter BLE Central plugin on iOS.

 **Responsibilities:**
 - Start and stop BLE scans
 - Track discovered peripherals
 - Check Bluetooth permission state
 - Trigger the iOS Bluetooth permission prompt when needed
 - Forward scan results and state changes to Flutter handlers

 This class mirrors the responsibilities of `FlutterBleCentralManager` on Android,
 but uses iOS CoreBluetooth APIs.
 */
final class FlutterBleCentralManager {

    /// The underlying CoreBluetooth central manager.
    private let centralManager: CBCentralManager

    /// Delegate responsible for handling scan results and state changes.
    private let centralManagerDelegate: CentralManagerDelegate

    /// Indicates whether a BLE scan is currently active.
    private(set) var isScanning = false

    /// Map of discovered peripherals by their `UUID`.
    private(set) var activePeripherals = [PeripheralID: CBPeripheral]()

    /**
     Initializes the BLE Central Manager.

     - Parameters:
       - scanResultHandler: Handler that publishes scan results to Flutter.
       - stateChangedHandler: Handler that publishes state changes to Flutter.
     */
    init(
        scanResultHandler: ScanResultHandler,
        stateChangedHandler: StateChangedHandler
    ) {
        self.centralManagerDelegate = CentralManagerDelegate(
            onStateChange: { state in
                stateChangedHandler.publishPeripheralState(state: state)
            },
            onDiscovery: { peripheral, advertisementData, rssi in
                scanResultHandler.publishScanResult(
                    advertiseData: advertisementData,
                    rssi: rssi,
                    peripheral: peripheral
                )
            }
        )

        self.centralManager = CBCentralManager(
            delegate: self.centralManagerDelegate,
            queue: nil
        )
    }

    /**
     Starts scanning for Bluetooth peripherals.

     - Parameter services: An optional array of `CBUUID`s to filter peripherals by.
     */
    func startScan(with services: [ServiceID]?) {
        isScanning = true
        if centralManager.state != .poweredOn {
            print("CBCentralManager must be powered on to scan peripherals. Current state: \(centralManager.state.rawValue)")
        }
        centralManager.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    /// Stops scanning for peripherals.
    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    /**
     Returns the current Bluetooth permission state mapped to `CentralState`.

     iOS triggers the permission dialog automatically when the
     authorization status is `.notDetermined` and a `CBCentralManager`
     is created.

     - Returns: A `CentralState` representing the current authorization status.
     */
    var permissionState: FlutterBleCentralState {
        if #available(iOS 13.1, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways:
                return .Granted
            case .denied:
                return .PermanentlyDenied
            case .restricted:
                return .Restricted
            case .notDetermined:
                return .Denied
            @unknown default:
                return .Unknown
            }
        } else if #available(iOS 13.0, *) {
            switch centralManager.authorization {
            case .allowedAlways:
                return .Granted
            case .denied:
                return .PermanentlyDenied
            case .restricted:
                return .Restricted
            case .notDetermined:
                return .Denied
            @unknown default:
                return .Unknown
            }
        } else {
            // Before iOS 13, Bluetooth permissions are not required.
            return .Granted
        }
    }

    /// Convenience boolean indicating whether Bluetooth permission has been granted.
    var hasPermissions: Bool {
        return permissionState == .Granted
    }

    /**
     Returns the current Bluetooth adapter state mapped to `CentralState`.

     This checks the actual hardware/software state of the Bluetooth adapter,
     not just the authorization status.

     - Returns: A `CentralState` representing the current adapter state.
     */
    var bluetoothState: FlutterBleCentralState {
        switch centralManager.state {
        case .poweredOn:
            return .Ready
        case .poweredOff:
            return .TurnedOff
        case .resetting:
            return .Unknown
        case .unauthorized:
            return .Denied
        case .unsupported:
            return .Unsupported
        case .unknown:
            return .Unknown
        @unknown default:
            return .Unknown
        }
    }

    /**
     Returns the combined state considering both permissions and Bluetooth adapter state.

     This method checks:
     1. Permission/authorization status
     2. Whether Bluetooth is actually powered on

     - Returns: A `CentralState` representing the overall readiness state.
     */
    func getCombinedState() -> FlutterBleCentralState {
        // First check permissions
        let permState = permissionState
        if permState != .Granted {
            return permState
        }

        // If permissions are granted, check Bluetooth adapter state
        return bluetoothState
    }

    /**
     Attempts to request Bluetooth permission by triggering the system dialog if needed.

     - Parameter completion: Called with the resulting `CentralState`.
     */
    func requestPermission(completion: @escaping (FlutterBleCentralState) -> Void) {
        switch permissionState {
        case .Denied:
            // Trigger the system dialog if status is notDetermined
            _ = CBCentralManager(delegate: nil, queue: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(self.permissionState)
            }
        default:
            completion(permissionState)
        }
    }

    /// Local error definitions for BLE operation failures.
    private enum Failure: Error, CustomStringConvertible {
        case notPoweredOn(actualState: CBManagerState)
        case peripheralIsUnknown(PeripheralID)
        case peripheralIsNotConnected(PeripheralID)
        case serviceNotFound(ServiceID, PeripheralID)

        var description: String {
            switch self {
            case .notPoweredOn(let actualState):
                return "Bluetooth is not powered on (the current state code is \(actualState.rawValue))"
            case .peripheralIsUnknown(let peripheralID):
                return "Peripheral \(peripheralID.uuidString) is unknown (make sure it has been discovered)"
            case .peripheralIsNotConnected(let peripheralID):
                return "Peripheral \(peripheralID.uuidString) is not connected"
            case .serviceNotFound(let serviceID, let peripheralID):
                return "Service \(serviceID) not found on peripheral \(peripheralID)"
            }
        }
    }
}
