#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import AppKit
#endif
import CoreBluetooth

/**
 The `FlutterBleCentralPlugin` class is the main entry point for the
 Flutter BLE Central plugin on iOS.

 **Responsibilities:**
 - Registers the plugin with the Flutter engine.
 - Handles method channel calls from the Flutter side.
 - Delegates BLE operations to [FlutterBleCentralManager].
 - Manages scan start/stop actions and permission checks.
 - Opens system settings when requested.

 This class mirrors the structure of the Android plugin class,
 ensuring consistent API behavior across platforms.
 */
public class FlutterBleCentralPlugin: NSObject, FlutterPlugin {
    
    /// The BLE manager responsible for scanning and permission handling.
    private let flutterBleCentralManager: FlutterBleCentralManager

    /// Handler that publishes scan results to Flutter event channels.
    private let scanResultHandler: ScanResultHandler

    /// Handler that publishes state changes (e.g., Bluetooth state updates) to Flutter event channels.
    private let stateChangedHandler: StateChangedHandler

    /// Handler that publishes connection state changes to Flutter.
    private let connectionStateHandler: ConnectionEventHandler

    /// Handler that publishes notified characteristic values to Flutter.
    private let characteristicValueHandler: ConnectionEventHandler

    /// Registered so an app that listens to it unconditionally does not fail on
    /// a missing channel. Core Bluetooth exposes no pairing API, so nothing is
    /// ever published here.
    private let bondStateHandler: ConnectionEventHandler

    /**
     Initializes the plugin with scan and state change handlers.

     - Parameters:
       - scanResultHandler: The handler for publishing scan results to Flutter.
       - stateChangedHandler: The handler for publishing Bluetooth state changes to Flutter.
       - connectionStateHandler: The handler for publishing connection state changes.
       - characteristicValueHandler: The handler for publishing notified values.
       - bondStateHandler: The handler for the bond state stream, unused on Apple.
     */
    init(
        scanResultHandler: ScanResultHandler,
        stateChangedHandler: StateChangedHandler,
        connectionStateHandler: ConnectionEventHandler,
        characteristicValueHandler: ConnectionEventHandler,
        bondStateHandler: ConnectionEventHandler
    ) {
        self.scanResultHandler = scanResultHandler
        self.stateChangedHandler = stateChangedHandler
        self.connectionStateHandler = connectionStateHandler
        self.characteristicValueHandler = characteristicValueHandler
        self.bondStateHandler = bondStateHandler
        self.flutterBleCentralManager = FlutterBleCentralManager(
            scanResultHandler: scanResultHandler,
            stateChangedHandler: stateChangedHandler,
            connectionStateHandler: connectionStateHandler,
            characteristicValueHandler: characteristicValueHandler
        )
        super.init()
    }
    
    /**
     Registers the plugin with the Flutter engine.

     This sets up the method channel and associates the plugin instance
     with incoming Flutter method calls.
     */
    public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
        let channel = FlutterMethodChannel(
            name: "dev.steenbakker.flutter_ble_central/method",
            binaryMessenger: messenger
        )
        let instance = FlutterBleCentralPlugin(
            scanResultHandler: ScanResultHandler(registrar: registrar),
            stateChangedHandler: StateChangedHandler(registrar: registrar),
            connectionStateHandler: ConnectionEventHandler(
                registrar: registrar,
                name: "dev.steenbakker.flutter_ble_central/connection_state"
            ),
            characteristicValueHandler: ConnectionEventHandler(
                registrar: registrar,
                name: "dev.steenbakker.flutter_ble_central/characteristic_value"
            ),
            bondStateHandler: ConnectionEventHandler(
                registrar: registrar,
                name: "dev.steenbakker.flutter_ble_central/bond_state"
            )
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /**
     Handles incoming method calls from Flutter.

     Supported methods:
     - `"start"` → Start scanning for BLE peripherals
     - `"stop"` → Stop scanning
     - `"isSupported"` → Check if BLE is supported
     - `"isBluetoothOn"` → Check if Bluetooth is powered on
     - `"enableBluetooth"` → Not supported on Apple platforms
     - `"openAppSettings"` → Open app settings
     - `"openBluetoothSettings"` → Open Bluetooth settings
     - `"hasPermission"` → Return current Bluetooth permission state
     - `"requestPermission"` → Trigger permission request if needed
     */
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startScan(call, result: result)
        case "stop":
            stopScan(result)
        case "isSupported":
            result(flutterBleCentralManager.bluetoothState != .Unsupported)
        case "isBluetoothOn":
            result(flutterBleCentralManager.bluetoothState == .Ready)
        case "enableBluetooth":
            // Cannot programmatically enable Bluetooth on iOS/macOS
            result(false)
        case "openBluetoothSettings":
            openBluetoothSettings()
            result(nil)
        case "openAppSettings":
            openAppSettings()
            result(nil)
        case "hasPermission":
            result(getPermissionState())
        case "requestPermission":
            // On iOS/macOS, permissions are requested implicitly when using Bluetooth
            // The CBCentralManager initialization triggers the permission request
            result(getPermissionState())

        // Core Bluetooth exposes none of these, so they are refused by name
        // rather than left to fail as a missing plugin.
        case "createBond", "removeBond", "getBondState",
             "requestConnectionPriority", "readPhy", "setPreferredPhy",
             "beginReliableWrite", "executeReliableWrite", "abortReliableWrite":
            result(FlutterError(
                code: "unsupported",
                message: "\(call.method) is not available on iOS or macOS",
                details: nil
            ))

        default:
            handleConnectionMethod(call, result: result)
        }
    }

    /**
     Serves the GATT client half.

     Everything Dart sent is read here, on the platform thread, so a call that is
     missing an argument is refused before it reaches Core Bluetooth.

     - Parameters:
       - call: The method call and its arguments.
       - result: The Flutter result callback, answered once the operation is done.
     */
    private func handleConnectionMethod(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let gatt = flutterBleCentralManager.gatt!
        let arguments = call.arguments as? [String: Any] ?? [:]

        func invalid(_ message: String) {
            result(FlutterError(
                code: "INVALID_ARGUMENTS", message: message, details: nil
            ))
        }

        guard let address = arguments["address"] as? String else {
            // Not a connection method at all; nothing here serves it.
            if call.method == "connect" || call.method == "disconnect" {
                invalid("address is required")
            } else {
                result(FlutterMethodNotImplemented)
            }
            return
        }

        // The uuids the operation addresses, normalised the way discovery
        // reported them so they match whatever Dart sends back. Parsed here
        // rather than deeper in, since a malformed one has to reach Dart as an
        // error instead of reaching CBUUID, which would take the app down.
        var malformed: String?
        func uuid(_ key: String) -> String? {
            guard let text = arguments[key] as? String else { return nil }
            guard let parsed = GattConnectionManager.parseUuid(text) else {
                malformed = text
                return nil
            }
            return GattConnectionManager.fullUuid(parsed)
        }

        let serviceUuid = uuid("serviceUuid")
        let characteristicUuid = uuid("characteristicUuid")
        let descriptorUuid = uuid("descriptorUuid")

        if let malformed = malformed {
            invalid("Invalid uuid: \(malformed)")
            return
        }

        switch call.method {
        case "connect":
            gatt.connect(
                address: address,
                timeout: arguments["timeout"] as? Int ?? 0,
                result: result
            )
        case "disconnect":
            gatt.disconnect(address: address, result: result)
        case "getConnectionState":
            gatt.connectionState(address: address, result: result)
        case "discoverServices":
            gatt.discoverServices(address: address, result: result)
        case "requestMtu":
            gatt.mtu(address: address, result: result)
        case "readRssi":
            gatt.readRssi(address: address, result: result)

        case "readCharacteristic":
            guard let serviceUuid = serviceUuid,
                  let characteristicUuid = characteristicUuid else {
                invalid("serviceUuid and characteristicUuid are required")
                return
            }
            gatt.readCharacteristic(
                address: address, serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid, result: result
            )

        case "writeCharacteristic":
            guard let serviceUuid = serviceUuid,
                  let characteristicUuid = characteristicUuid,
                  let value = Self.readBytes(arguments["value"]) else {
                invalid("serviceUuid, characteristicUuid and value are required")
                return
            }
            gatt.writeCharacteristic(
                address: address, serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid, value: value,
                withoutResponse: arguments["withoutResponse"] as? Bool ?? false,
                result: result
            )

        case "setCharacteristicNotification":
            guard let serviceUuid = serviceUuid,
                  let characteristicUuid = characteristicUuid else {
                invalid("serviceUuid and characteristicUuid are required")
                return
            }
            gatt.setCharacteristicNotification(
                address: address, serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid,
                enable: arguments["enable"] as? Bool ?? false, result: result
            )

        case "readDescriptor":
            guard let serviceUuid = serviceUuid,
                  let characteristicUuid = characteristicUuid,
                  let descriptorUuid = descriptorUuid else {
                invalid("serviceUuid, characteristicUuid and descriptorUuid are required")
                return
            }
            gatt.readDescriptor(
                address: address, serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid,
                descriptorUuid: descriptorUuid, result: result
            )

        case "writeDescriptor":
            guard let serviceUuid = serviceUuid,
                  let characteristicUuid = characteristicUuid,
                  let descriptorUuid = descriptorUuid,
                  let value = Self.readBytes(arguments["value"]) else {
                invalid("serviceUuid, characteristicUuid, descriptorUuid and value are required")
                return
            }
            gatt.writeDescriptor(
                address: address, serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid,
                descriptorUuid: descriptorUuid, value: value, result: result
            )

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Accepts both the byte buffer Dart sends for a `Uint8List` and the list of
    /// ints it falls back to.
    private static func readBytes(_ value: Any?) -> Data? {
        if let typed = value as? FlutterStandardTypedData { return typed.data }
        if let data = value as? Data { return data }
        if let list = value as? [NSNumber] {
            return Data(list.map { $0.uint8Value })
        }
        return nil
    }

    // Returns permission state ordinal matching CentralBluetoothState enum
    // Note: This checks PERMISSION status only, not Bluetooth power state (use isBluetoothOn for that)
    private func getPermissionState() -> Int {
        // First try the authorization API (iOS 13.1+/macOS 10.15+)
        // This gives us permission status regardless of Bluetooth power state
        if #available(iOS 13.1, macOS 10.15, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways:
                return CentralBluetoothState.Granted.rawValue
            case .denied:
                return CentralBluetoothState.PermanentlyDenied.rawValue
            case .restricted:
                return CentralBluetoothState.Restricted.rawValue
            case .notDetermined:
                return CentralBluetoothState.Denied.rawValue
            @unknown default:
                break // fall through to state-based check
            }
        }

        // Fallback: return the permission state from the manager
        return flutterBleCentralManager.permissionState.rawValue
    }

    private func openBluetoothSettings() {
#if os(iOS)
        // Cannot open bluetooth settings directly, open app settings instead
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#else
        // Open System Settings to Bluetooth pane on macOS
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
#endif
    }

    private func openAppSettings() {
#if os(iOS)
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
#else
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
#endif
    }
    
    /**
     Starts BLE scanning using the Flutter BLE Central Manager.

     This method checks both permissions and Bluetooth adapter state before starting the scan,
     similar to the Android implementation.

     - Parameter result: The Flutter result callback used to send back the operation state.
     */
    private func startScan(_ result: @escaping FlutterResult) {
        // Check combined state (permissions + Bluetooth adapter state)
        let state = flutterBleCentralManager.getCombinedState()

        // Only start scanning if Bluetooth is ready
        if state == .Ready || state == .Granted {
            flutterBleCentralManager.startScan(with: nil)
            result(CentralBluetoothState.Ready.rawValue)
        } else {
            // Return the error state (TurnedOff, Denied, Unsupported, etc.)
            result(state.rawValue)
        }
    }

    /**
     Starts BLE scanning with settings from Flutter.

     - Parameters:
       - call: The method call containing scan settings.
       - result: The Flutter result callback used to send back the operation state.
     */
    private func startScan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let arguments = call.arguments as? [String: Any],
           let enableTimingStats = arguments["enableTimingStats"] as? Bool {
            scanResultHandler.setEnableTimingStats(enableTimingStats)
        }
        startScan(result)
    }
    
    /**
     Stops BLE scanning.
     
     - Parameter result: The Flutter result callback used to send back the operation state.
     */
    private func stopScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.stopScan()
        result(CentralBluetoothState.Ready.rawValue)
    }
}
