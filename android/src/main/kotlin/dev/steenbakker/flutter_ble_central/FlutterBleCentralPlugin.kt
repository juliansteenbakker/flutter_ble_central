package dev.steenbakker.flutter_ble_central

import android.bluetooth.le.ScanSettings
import android.bluetooth.le.ScanSettings.SCAN_MODE_BALANCED
import android.bluetooth.le.ScanSettings.SCAN_MODE_LOW_LATENCY
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import io.flutter.Log

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** FlutterBleCentralPlugin */
class FlutterBleCentralPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel

  private var flutterBleCentralManager: FlutterBleCentralManager? = null

  private lateinit var scanResultHandler: ScanResultHandler

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.steenbakker.flutter_ble_central/method")
    channel.setMethodCallHandler(this)

    scanResultHandler = ScanResultHandler(flutterPluginBinding)

    try {
      flutterBleCentralManager = FlutterBleCentralManager(flutterPluginBinding.applicationContext, scanResultHandler)
    } catch (e: Exception) {
//      stateChangedHandler.publishPeripheralState(e.state)
//      Log.e(tag, e.state.name)
      return
    }
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (flutterBleCentralManager == null) {
      result.error("Not initialized", "FlutterBlePeripheral is not correctly initialized", "null")
    }
    when (call.method) {
      "start" -> startScan(call, result)
      "stop" -> stopScan(call, result)
//      "isAdvertising" -> Handler(Looper.getMainLooper()).post {
//        result.success(flutterBlePeripheralManager?.isAdvertising())
//      }
//      "isSupported" -> isSupported(result, context!!)
//      "isConnected" -> isConnected(result)
//      "sendData" -> sendData(call, result)
//      "enableBluetooth" -> enableBluetooth(call, result)
      else -> Handler(Looper.getMainLooper()).post {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  private fun startScan(call: MethodCall, result: MethodChannel.Result) {
    val scanSettings = ScanSettings.Builder()
    scanSettings.setScanMode(SCAN_MODE_LOW_LATENCY)
    flutterBleCentralManager?.startScan(scanSettings.build(), result)
  }

  private fun stopScan(call: MethodCall, result: MethodChannel.Result) {
    flutterBleCentralManager?.stopScan()
    result.success(null)
  }
}
