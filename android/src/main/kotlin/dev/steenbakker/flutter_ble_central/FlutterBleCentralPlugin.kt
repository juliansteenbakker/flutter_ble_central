package dev.steenbakker.flutter_ble_central

import dev.steenbakker.flutter_ble_central.callbacks.ScanResultCallback
import android.Manifest
import android.app.Activity
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import dev.steenbakker.flutter_ble_central.handlers.StateChangedHandler
import dev.steenbakker.flutter_ble_central.models.CentralState

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** FlutterBleCentralPlugin */
class FlutterBleCentralPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

  private lateinit var channel : MethodChannel
  private lateinit var stateChangedHandler: StateChangedHandler
  private lateinit var scanResultHandler: ScanResultHandler
  private lateinit var scanErrorHandler: ScanErrorHandler

  private var flutterBleCentralManager: FlutterBleCentralManager? = null
  private var context: Context? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var scanCallback: ScanResultCallback? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.steenbakker.flutter_ble_central/method")
    channel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext
    scanResultHandler = ScanResultHandler(flutterPluginBinding)
    scanErrorHandler = ScanErrorHandler(flutterPluginBinding)
    stateChangedHandler = StateChangedHandler(flutterPluginBinding)
    flutterBleCentralManager = FlutterBleCentralManager(flutterPluginBinding.applicationContext)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (flutterBleCentralManager == null || context == null) {
      result.error("Not initialized", "FlutterBleCentral is not correctly initialized", null)
    }
    if (call.method == "start" || call.method == "stop") {
      val state = checkBluetoothState()
      if (state != null) {
        result.error(state.value.toString(), state.name, "startAdvertising")
        return
      }
    }

    when (call.method) {
      "start" -> startScan(call, result)
      "stop" -> stopScan(result)
      "isSupported" -> isSupported(result, context!!)
      "enableBluetooth" -> enableBluetooth(call, result)
      "requestPermission" -> Handler(Looper.getMainLooper()).post {
        flutterBleCentralManager!!.pendingResultForPermissionResult = result
        flutterBleCentralManager!!.requestPermission(activityBinding!!)
      }
      "hasPermission" -> Handler(Looper.getMainLooper()).post {
        result.success(flutterBleCentralManager!!.requestPermission(activityBinding!!))
      }
      else -> Handler(Looper.getMainLooper()).post {
        result.notImplemented()
      }
    }
  }

  private fun startScan(call: MethodCall, result: Result) {
    if (call.arguments !is Map<*, *>) {
      throw IllegalArgumentException("Arguments are not a map! " + call.arguments)
    }

    val arguments = call.arguments as Map<*, *>

    val scanSettings = ScanSettings.Builder()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      (arguments["legacyMode"] as Boolean?)?.let { scanSettings.setLegacy((arguments["legacyMode"] as Boolean)) }
      (arguments["phy"] as Int?)?.let { scanSettings.setPhy((arguments["phy"] as Int)) }
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      (arguments["callbackType"] as Int?)?.let { scanSettings.setCallbackType((arguments["callbackType"] as Int)) }
      (arguments["matchMode"] as Int?)?.let { scanSettings.setMatchMode((arguments["matchMode"] as Int)) }
      (arguments["numOfMatches"] as Int?)?.let { scanSettings.setNumOfMatches((arguments["numOfMatches"] as Int)) }
    }

    (arguments["reportDelay"] as Int?)?.let { scanSettings.setReportDelay((arguments["reportDelay"] as Int).toLong()) }
    (arguments["scanMode"] as Int?)?.let { scanSettings.setScanMode((arguments["scanMode"] as Int)) }

    scanCallback = ScanResultCallback(scanResultHandler, scanErrorHandler)
    flutterBleCentralManager?.startScan(scanSettings.build(), result, scanCallback!!)
  }

  private fun stopScan(result: Result) {
    if (scanCallback != null) {
      flutterBleCentralManager?.stopScan(scanCallback!!)
    }
    result.success(null)
  }

  private fun isSupported(result: Result, context: Context) {
    val isSupported = context.packageManager?.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)

    Handler(Looper.getMainLooper()).post {
      result.success(isSupported)
    }
  }

  private fun checkBluetoothState(): CentralState? {
    if (flutterBleCentralManager!!.mBluetoothManager == null || flutterBleCentralManager!!.mBluetoothManager?.adapter == null) {
      return CentralState.unsupported
    } else {
      // Can't check whether ble is turned off or not supported, see https://stackoverflow.com/questions/32092902/why-ismultipleadvertisementsupported-returns-false-when-getbluetoothleadverti
      // !bluetoothAdapter.isMultipleAdvertisementSupported
      flutterBleCentralManager!!.mBluetoothLeScanner = flutterBleCentralManager!!.mBluetoothManager!!.adapter.bluetoothLeScanner
      if (!flutterBleCentralManager!!.mBluetoothManager!!.adapter.isEnabled) {
        flutterBleCentralManager!!.enableBluetooth(true, null, activityBinding!!)
        return CentralState.poweredOff
      } else {
        val hasPermission = flutterBleCentralManager!!.requestPermission(activityBinding!!)
        if (!hasPermission) return CentralState.unauthorized
      }
    }
    return null
  }

  private fun enableBluetooth(call: MethodCall, result: Result) {
    if (activityBinding != null) {
      this.shouldAsk = call.arguments as Boolean
      flutterBleCentralManager!!.checkAndEnableBluetooth(call, result, activityBinding!!)
    } else {
      result.error("No activity", "FlutterBlePeripheral is not correctly initialized", "null")
    }
  }

  private var shouldAsk: Boolean? = null

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode == FlutterBleCentralManager.REQUEST_PERMISSION_BT) {
      var hasAllPermissions = true
      for (i in permissions.indices) {
        val permission = permissions[i]
        val grantResult = grantResults[i]
        if (permission == Manifest.permission.BLUETOOTH_CONNECT || permission == Manifest.permission.BLUETOOTH_ADVERTISE || permission == Manifest.permission.ACCESS_FINE_LOCATION || permission == Manifest.permission.ACCESS_COARSE_LOCATION) {
          if (grantResult == PackageManager.PERMISSION_DENIED) {
            hasAllPermissions = false
          }
        }
      }

      if (hasAllPermissions) {
        if (shouldAsk != null && activityBinding != null) {
          flutterBleCentralManager?.enableBluetooth(true, flutterBleCentralManager?.pendingResultForPermissionResult!!, activityBinding!! )
          return true
        }
      }

      flutterBleCentralManager?.pendingResultForPermissionResult?.success(hasAllPermissions)
      flutterBleCentralManager?.pendingResultForPermissionResult = null
    }

    return false
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addRequestPermissionsResultListener(this)
    binding.addActivityResultListener { requestCode, resultCode, _ ->
      when (requestCode) {
        FlutterBleCentralManager.REQUEST_ENABLE_BT -> {
          if (flutterBleCentralManager?.pendingResultForActivityResult != null) {
            flutterBleCentralManager!!.pendingResultForActivityResult!!.success(resultCode == Activity.RESULT_OK)
          }
          flutterBleCentralManager?.pendingResultForActivityResult = null
          return@addActivityResultListener true
        }
        else -> return@addActivityResultListener false
      }
    }
    activityBinding = binding
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    activityBinding = null
  }
}
