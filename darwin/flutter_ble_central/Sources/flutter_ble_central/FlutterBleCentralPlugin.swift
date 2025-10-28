#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import AppKit
#endif

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
     - `"openAppSettings"` → Open system settings
     - `"hasPermission"` → Return current Bluetooth permission state
     - `"requestPermission"` → Trigger permission request if needed
     */
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startScan(result)
        case "stop":
            stopScan(result)
        case "openAppSettings":
#if os(iOS)
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
#else
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
#endif
            result(nil)
        case "hasPermission", "requestPermission":
            result(flutterBleCentralManager.permissionState.rawValue)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /**
     Starts BLE scanning using the Flutter BLE Central Manager.
     
     - Parameter result: The Flutter result callback used to send back the operation state.
     */
    private func startScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.startScan(with: nil)
        result(CentralState.Ready.rawValue)
    }
    
    /**
     Stops BLE scanning.
     
     - Parameter result: The Flutter result callback used to send back the operation state.
     */
    private func stopScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.stopScan()
        result(CentralState.Ready.rawValue)
    }
}
