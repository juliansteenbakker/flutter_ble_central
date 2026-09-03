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

    /// The identifier Core Bluetooth hands the connected peripherals back under,
    /// after it relaunched the app into the background.
    static let restoreIdentifier = "dev.steenbakker.flutter_ble_central.central_manager"

    /// Whether the app declares the `bluetooth-central` background mode, which is
    /// what keeps a scan and a connection alive once the app is no longer in front,
    /// and what lets Core Bluetooth relaunch the app to hand its state back.
    static var declaresCentralBackgroundMode: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("bluetooth-central") ?? false
    }

    /// Delegate responsible for handling scan results and state changes.
    private let centralManagerDelegate: CentralManagerDelegate

    /// Indicates whether a BLE scan is currently active.
    private(set) var isScanning = false

    /// Map of discovered peripherals by their `UUID`.
    private(set) var activePeripherals = [PeripheralID: CBPeripheral]()

    /// Serves the GATT client half: connections, discovery, reads and writes.
    /// Built in `init`, after the central manager it works through.
    private(set) var gatt: GattConnectionManager!

    /// Queue CoreBluetooth delivers its callbacks on.
    ///
    /// Deliberately not the main queue: with duplicates allowed, every advertising
    /// event is reported and parsed, which would otherwise compete with the Flutter
    /// UI. Serial, to keep CoreBluetooth's callback ordering; only the
    /// `FlutterEventSink` call hops back to main, as required for Flutter channels.
    private let callbackQueue = DispatchQueue(
        label: "dev.steenbakker.flutter_ble_central.callback",
        qos: .userInitiated
    )

    /**
     Initializes the BLE Central Manager.

     - Parameters:
       - scanResultHandler: Handler that publishes scan results to Flutter.
       - stateChangedHandler: Handler that publishes state changes to Flutter.
       - connectionStateHandler: Handler that publishes connection state changes.
       - characteristicValueHandler: Handler that publishes notified values.
     */
    init(
        scanResultHandler: ScanResultHandler,
        stateChangedHandler: StateChangedHandler,
        connectionStateHandler: ConnectionEventHandler,
        characteristicValueHandler: ConnectionEventHandler
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

        var options: [String: Any] = [:]
#if os(iOS)
        // Only an app that stays connected in the background is ever relaunched to
        // be handed its state back, so the identifier is set exactly when it asked
        // for that. Handing one to an app without the background mode would leave
        // Core Bluetooth holding state it can never give back.
        if FlutterBleCentralManager.declaresCentralBackgroundMode {
            options[CBCentralManagerOptionRestoreIdentifierKey] =
                FlutterBleCentralManager.restoreIdentifier
        }
#endif

        self.centralManager = CBCentralManager(
            delegate: self.centralManagerDelegate,
            queue: callbackQueue,
            options: options
        )

        // Built after the central manager, since it needs it, and wired into the
        // delegate afterwards for the same reason. Each of these arrives on
        // `callbackQueue`, which is where the GATT manager keeps its state.
        self.gatt = GattConnectionManager(
            centralManager: centralManager,
            queue: callbackQueue,
            connectionStateHandler: connectionStateHandler,
            characteristicValueHandler: characteristicValueHandler
        )
        centralManagerDelegate.onConnect = { [weak self] peripheral, _ in
            self?.gatt.handleDidConnect(peripheral)
        }
        centralManagerDelegate.onConnectFailed = { [weak self] peripheral, error in
            self?.gatt.handleDidFailToConnect(peripheral, error: error)
        }
        centralManagerDelegate.onDisconnect = { [weak self] peripheral, error in
            self?.gatt.handleDidDisconnect(peripheral, error: error)
        }
        centralManagerDelegate.onRestore = { [weak self] peripherals in
            self?.gatt.restore(peripherals)
        }
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
    var permissionState: CentralBluetoothState {
        if #available(iOS 13.1, macOS 10.15, *) {
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
    var bluetoothState: CentralBluetoothState {
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
    func getCombinedState() -> CentralBluetoothState {
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
    func requestPermission(completion: @escaping (CentralBluetoothState) -> Void) {
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
