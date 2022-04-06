import Flutter
import UIKit

public class SwiftFlutterBleCentralPlugin: NSObject, FlutterPlugin {
    
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
    let channel = FlutterMethodChannel(name: "dev.steenbakker.flutter_ble_central/method", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterBleCentralPlugin(scanResultHandler: ScanResultHandler(registrar: registrar), stateChangedHandler: StateChangedHandler(registrar: registrar))
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch (call.method) {
      case "start":
          startScan(result)
      case "stop":
          stopScan(result)
      default:
          result(FlutterMethodNotImplemented)
      }
  }
    
    private func startScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.startScan(with: nil)
        result(nil)
    }
    
    private func stopScan(_ result: @escaping FlutterResult) {
        flutterBleCentralManager.stopScan()
        result(nil)
    }
}
