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
    init(scanResultHandler: ScanResultHandler, stateChangedHandler: StateChangedHandler) {
        self.scanResultHandler = scanResultHandler
        self.stateChangedHandler = stateChangedHandler
        self.flutterBleCentralManager = FlutterBleCentralManager(
            scanResultHandler: scanResultHandler,
            stateChangedHandler: stateChangedHandler
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
            stateChangedHandler: StateChangedHandler(registrar: registrar)
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
}
