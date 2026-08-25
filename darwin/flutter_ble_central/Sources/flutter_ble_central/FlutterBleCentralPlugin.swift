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

    /**
     Initializes the plugin with scan and state change handlers.

     - Parameters:
       - scanResultHandler: The handler for publishing scan results to Flutter.
       - stateChangedHandler: The handler for publishing Bluetooth state changes to Flutter.
     */
    init(
        scanResultHandler: ScanResultHandler,
        stateChangedHandler: StateChangedHandler,
        connectionStateHandler: ConnectionStateHandler,
        characteristicValueHandler: CharacteristicValueHandler
    ) {
        self.scanResultHandler = scanResultHandler
        self.stateChangedHandler = stateChangedHandler
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
            connectionStateHandler: ConnectionStateHandler(messenger: messenger),
            characteristicValueHandler: CharacteristicValueHandler(messenger: messenger)
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

        // Connection management
        case "connect":
            withAddress(call, result) { address in
                try self.gatt.connect(address: address)
                result(nil)
            }
        case "disconnect":
            withAddress(call, result) { address in
                try self.gatt.disconnect(address: address)
                result(nil)
            }
        case "getConnectionState":
            withAddress(call, result) { address in
                result(self.gatt.connectionState(address: address))
            }

        // Service discovery
        case "discoverServices":
            withAddress(call, result) { address in
                self.gatt.discoverServices(address: address) { discovery in
                    self.finish(discovery, result)
                }
            }

        // Characteristic operations
        case "readCharacteristic":
            withArguments(call, result) { args in
                self.gatt.readCharacteristic(
                    address: try args.string("address"),
                    serviceUuid: try args.string("serviceUuid"),
                    characteristicUuid: try args.string("characteristicUuid")
                ) { read in
                    self.finish(read.map { FlutterStandardTypedData(bytes: $0) }, result)
                }
            }
        case "writeCharacteristic":
            withArguments(call, result) { args in
                self.gatt.writeCharacteristic(
                    address: try args.string("address"),
                    serviceUuid: try args.string("serviceUuid"),
                    characteristicUuid: try args.string("characteristicUuid"),
                    value: try args.data("value"),
                    withoutResponse: args.bool("withoutResponse") ?? false
                ) { write in
                    self.finishVoid(write, result)
                }
            }
        case "setCharacteristicNotification":
            withArguments(call, result) { args in
                self.gatt.setNotify(
                    address: try args.string("address"),
                    serviceUuid: try args.string("serviceUuid"),
                    characteristicUuid: try args.string("characteristicUuid"),
                    enable: args.bool("enable") ?? false
                ) { notify in
                    self.finishVoid(notify, result)
                }
            }

        // Descriptor operations
        case "readDescriptor":
            withArguments(call, result) { args in
                self.gatt.readDescriptor(
                    address: try args.string("address"),
                    serviceUuid: try args.string("serviceUuid"),
                    characteristicUuid: try args.string("characteristicUuid"),
                    descriptorUuid: try args.string("descriptorUuid")
                ) { read in
                    self.finish(read.map { FlutterStandardTypedData(bytes: $0) }, result)
                }
            }
        case "writeDescriptor":
            withArguments(call, result) { args in
                self.gatt.writeDescriptor(
                    address: try args.string("address"),
                    serviceUuid: try args.string("serviceUuid"),
                    characteristicUuid: try args.string("characteristicUuid"),
                    descriptorUuid: try args.string("descriptorUuid"),
                    value: try args.data("value")
                ) { write in
                    self.finishVoid(write, result)
                }
            }

        // Connection properties
        case "requestMtu":
            // CoreBluetooth negotiates the MTU itself, so the size asked for is
            // ignored and what it settled on is reported instead.
            withAddress(call, result) { address in
                result(try self.gatt.mtu(address: address))
            }
        case "readRssi":
            withAddress(call, result) { address in
                self.gatt.readRssi(address: address) { rssi in
                    self.finish(rssi, result)
                }
            }

        // Not available through CoreBluetooth
        case "createBond", "removeBond", "getBondState":
            // Pairing happens when a peripheral demands it and is driven by the
            // system, with no API to start it or read it back.
            result(unsupported("Pairing"))
        case "readPhy", "setPreferredPhy":
            result(unsupported("PHY control"))
        case "requestConnectionPriority":
            result(unsupported("Connection priority"))
        case "beginReliableWrite", "executeReliableWrite", "abortReliableWrite":
            result(unsupported("Reliable write"))

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // Returns permission state ordinal matching FlutterBleBluetoothState enum
    // Note: This checks PERMISSION status only, not Bluetooth power state (use isBluetoothOn for that)
    private func getPermissionState() -> Int {
        // First try the authorization API (iOS 13.1+/macOS 10.15+)
        // This gives us permission status regardless of Bluetooth power state
        if #available(iOS 13.1, macOS 10.15, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways:
                return FlutterBleBluetoothState.Granted.rawValue
            case .denied:
                return FlutterBleBluetoothState.PermanentlyDenied.rawValue
            case .restricted:
                return FlutterBleBluetoothState.Restricted.rawValue
            case .notDetermined:
                return FlutterBleBluetoothState.Denied.rawValue
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
            result(FlutterBleBluetoothState.Ready.rawValue)
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
        result(FlutterBleBluetoothState.Ready.rawValue)
    }

    // MARK: - Method call plumbing

    /// The connection manager the GATT cases run against.
    private var gatt: GattConnectionManager {
        return flutterBleCentralManager.gattConnectionManager
    }

    /// The arguments of a method call, read by name so a missing one is reported
    /// rather than crashing.
    private struct Arguments {
        let values: [String: Any]

        enum Missing: Error, CustomStringConvertible {
            case argument(String)

            var description: String {
                switch self {
                case .argument(let name): return "\(name) is required"
                }
            }
        }

        func string(_ name: String) throws -> String {
            guard let value = values[name] as? String else {
                throw Missing.argument(name)
            }
            return value
        }

        func bool(_ name: String) -> Bool? {
            return values[name] as? Bool
        }

        func data(_ name: String) throws -> Data {
            if let typed = values[name] as? FlutterStandardTypedData {
                return typed.data
            }
            if let bytes = values[name] as? [UInt8] {
                return Data(bytes)
            }
            throw Missing.argument(name)
        }
    }

    /// Runs [body] with the call's arguments, reporting a bad call to Flutter.
    private func withArguments(
        _ call: FlutterMethodCall,
        _ result: @escaping FlutterResult,
        _ body: (Arguments) throws -> Void
    ) {
        guard let values = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Arguments must be a map",
                details: nil
            ))
            return
        }
        do {
            try body(Arguments(values: values))
        } catch {
            result(error.asFlutterError)
        }
    }

    /// As `withArguments`, for the many calls that take only an address.
    private func withAddress(
        _ call: FlutterMethodCall,
        _ result: @escaping FlutterResult,
        _ body: (String) throws -> Void
    ) {
        withArguments(call, result) { args in
            try body(try args.string("address"))
        }
    }

    /// Hands a completed operation that returns nothing back to Flutter.
    private func finishVoid(
        _ outcome: Result<Void, Error>,
        _ result: @escaping FlutterResult
    ) {
        switch outcome {
        case .success:
            result(nil)
        case .failure(let error):
            result(error.asFlutterError)
        }
    }

    /// Hands a completed operation back to Flutter.
    private func finish<T>(_ outcome: Result<T, Error>, _ result: @escaping FlutterResult) {
        switch outcome {
        case .success(let value):
            result(value)
        case .failure(let error):
            result(error.asFlutterError)
        }
    }

    /// What the calls that CoreBluetooth has no answer for report back.
    private func unsupported(_ what: String) -> FlutterError {
        return FlutterError(
            code: "UNSUPPORTED",
            message: GattConnectionManager.Failure.unsupportedOnApple(what).description,
            details: nil
        )
    }
}

private extension Error {
    /// The error as Flutter reports it, keeping the manager's codes.
    var asFlutterError: FlutterError {
        if let failure = self as? GattConnectionManager.Failure {
            return FlutterError(
                code: failure.code,
                message: failure.description,
                details: nil
            )
        }
        return FlutterError(
            code: "OPERATION_FAILED",
            message: localizedDescription,
            details: nil
        )
    }
}
