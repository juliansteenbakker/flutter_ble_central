#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
  import AppKit
#endif

public class FlutterBleCentralPlugin: NSObject, FlutterPlugin {
    
    private let flutterBleCentralManager: FlutterBleCentralManager
    private let scanResultHandler: ScanResultHandler
    private let stateChangedHandler: StateChangedHandler
    
    init(scanResultHandler: ScanResultHandler, stateChangedHandler: StateChangedHandler) {
        self.scanResultHandler = scanResultHandler
        self.stateChangedHandler = stateChangedHandler
        flutterBleCentralManager = FlutterBleCentralManager(scanResultHandler: scanResultHandler, stateChangedHandler: stateChangedHandler)
        super.init()
    }
    
    
  public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
      
      
      let channel = FlutterMethodChannel(name: "dev.steenbakker.flutter_ble_central/method", binaryMessenger: messenger)
    let instance = FlutterBleCentralPlugin(scanResultHandler: ScanResultHandler(registrar: registrar), stateChangedHandler: StateChangedHandler(registrar: registrar))
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch (call.method) {
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
    case "hasPermission":
        result(flutterBleCentralManager.hasPermissions)
    case "requestPermission":
        result(flutterBleCentralManager.hasPermissions)
      default:
          result(FlutterMethodNotImplemented)
      }
  }
    
    private func startScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.startScan(with: nil)
        result(CentralState.Ready.rawValue)
    }
    
    private func stopScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.stopScan()
        result(CentralState.Ready.rawValue)
    }
}
