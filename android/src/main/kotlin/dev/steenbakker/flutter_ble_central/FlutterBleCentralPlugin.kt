package dev.steenbakker.flutter_ble_central

import dev.steenbakker.flutter_ble_central.callbacks.ScanResultCallback
import android.Manifest
import android.app.Activity
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import dev.steenbakker.flutter_ble_central.handlers.StateChangedHandler
import dev.steenbakker.flutter_ble_central.models.State

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

  private lateinit var methodChannel : MethodChannel
  private lateinit var stateChangedHandler: StateChangedHandler
  private lateinit var scanResultHandler: ScanResultHandler
  private lateinit var scanErrorHandler: ScanErrorHandler

  private var flutterBleCentralManager: FlutterBleCentralManager? = null
  private var context: Context? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var scanCallback: ScanResultCallback? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.steenbakker.flutter_ble_central/method")
    methodChannel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext
    scanResultHandler = ScanResultHandler(flutterPluginBinding)
    scanErrorHandler = ScanErrorHandler(flutterPluginBinding)
    stateChangedHandler = StateChangedHandler(flutterPluginBinding)
    flutterBleCentralManager = FlutterBleCentralManager(flutterPluginBinding.applicationContext)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
  }

  var startStopCall: MethodCall? = null
  var startStopResult: Result? = null

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (flutterBleCentralManager == null || context == null) {
      safeResult(result) {
        result.error("Not initialized", "FlutterBleCentral is not correctly initialized", null)
      }
      return
    }

    if (call.method == "start") {
      startStopCall = call
      startStopResult = result
      val state = checkBluetoothState(result)
      if (state != State.Ready) return
    }

    when (call.method) {
      "start" -> handleStart(call, result)
      "stop" -> handleStop(result)
      "isSupported" -> handleIsSupported(result)
      "enableBluetooth" -> handleEnableBluetooth(call, result)
      "requestPermission" -> handleRequestPermission(result)
      "hasPermission" -> handleHasPermission(result)
      "openAppSettings" -> handleOpenAppSettings(result)
      "openBluetoothSettings" -> handleOpenBluetoothSettings(result)
      else -> handleNotImplemented(result)
    }
  }

  private fun handleStart(call: MethodCall, result: Result) {
    startScan(call, result)
  }

  private fun handleStop(result: Result) {
    if (scanCallback != null) {
      flutterBleCentralManager?.stopScan(scanCallback!!)
    }
    safeResult(result) {
      result.success(State.Ready.ordinal)
    }
  }

  private fun handleIsSupported(result: Result) {
    val isSupported = context?.packageManager?.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
    safeResult(result) {
      result.success(isSupported)
    }
  }

  private fun handleEnableBluetooth(call: MethodCall, result: Result) {
    if (activityBinding != null) {
      val isEnabled = flutterBleCentralManager!!
        .checkAndEnableBluetooth(call.arguments as Boolean, result, activityBinding!!)
      safeResult(result) {
        result.success(isEnabled)
      }
    } else {
      safeResult(result) {
        result.error("No activity", "FlutterBlePeripheral is not correctly initialized", "null")
      }
    }
  }

  private fun handleRequestPermission(result: Result) {
    flutterBleCentralManager!!.requestPermission(activityBinding!!.activity, result)
    // result handling is done internally
  }

  private fun handleHasPermission(result: Result) {
    val permission = flutterBleCentralManager!!.requestPermission(activityBinding!!.activity, null).ordinal
    safeResult(result) {
      result.success(permission)
    }
  }

  private fun handleOpenAppSettings(result: Result) {
    activityBinding!!.activity.startActivity(
      Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context!!.packageName, null)
      )
    )
    safeResult(result) {
      result.success(null)
    }
  }

  private fun handleOpenBluetoothSettings(result: Result) {
    activityBinding!!.activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS), null)
    safeResult(result) {
      result.success(null)
    }
  }

  private fun handleNotImplemented(result: Result) {
    safeResult(result) {
      result.notImplemented()
    }
  }

  private fun safeResult(result: Result, block: () -> Unit) {
    Handler(Looper.getMainLooper()).post {
      try {
        block()
      } catch (e: Exception) {
        result.error("UNEXPECTED_ERROR", e.message, null)
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

    try {
      flutterBleCentralManager?.startScan(scanSettings.build(), scanCallback!!)
      safeResult(result) {
        result.success(State.Ready.ordinal)
      }
    } catch (e: Exception) {
      safeResult(result) {
        result.error("startScan", e.message, null)
      }
    }

  }

  private fun checkBluetoothState(result: Result): State {

    if (flutterBleCentralManager!!.mBluetoothManager == null || flutterBleCentralManager!!.mBluetoothManager?.adapter == null) {
      result.success(State.Unsupported.ordinal)
      startStopCall = null
      startStopResult = null
      return State.Unsupported
    } else {
      if (activityBinding == null) {
        result.error("No activity", "Activity is not attached", null)
        return State.Denied
      }

      // Can't check whether ble is turned off or not supported, see https://stackoverflow.com/questions/32092902/why-ismultipleadvertisementsupported-returns-false-when-getbluetoothleadverti
      // !bluetoothAdapter.isMultipleAdvertisementSupported
      flutterBleCentralManager!!.mBluetoothLeScanner = flutterBleCentralManager!!.mBluetoothManager!!.adapter.bluetoothLeScanner
      val hasPermissions = flutterBleCentralManager!!.requestPermission(activityBinding!!.activity, result)
      if (hasPermissions == State.Granted) {
        if (!flutterBleCentralManager!!.mBluetoothManager!!.adapter.isEnabled) {
          flutterBleCentralManager!!.enableBluetooth(true, result, activityBinding!!, true)
        } else {
          return State.Ready
        }
      }
      return hasPermissions
    }
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode == FlutterBleCentralManager.REQUEST_PERMISSION_BT) {
      var hasAllPermissions = true
      var shouldShowRationale = false
      for (i in permissions.indices) {
        val permission = permissions[i]
        val grantResult = grantResults[i]
        if (permission == Manifest.permission.BLUETOOTH_CONNECT || permission == Manifest.permission.BLUETOOTH_ADVERTISE || permission == Manifest.permission.ACCESS_FINE_LOCATION || permission == Manifest.permission.ACCESS_COARSE_LOCATION) {
          if (grantResult == PackageManager.PERMISSION_DENIED) {
            if (ActivityCompat.shouldShowRequestPermissionRationale(activityBinding!!.activity, permission)) {
              shouldShowRationale = true
            }
            hasAllPermissions = false
          }
        }
      }

      if (shouldShowRationale) {
        flutterBleCentralManager?.pendingResultForPermissionResult?.success(State.Denied.ordinal)
      } else if (!flutterBleCentralManager!!.mBluetoothManager!!.adapter.isEnabled && startStopCall != null && hasAllPermissions) {
        flutterBleCentralManager!!.enableBluetooth(true, flutterBleCentralManager?.pendingResultForPermissionResult, activityBinding!!, true)
      } else {
        if (hasAllPermissions) {
          if (startStopCall != null) {
            onMethodCall(startStopCall!!, flutterBleCentralManager!!.pendingResultForPermissionResult!!)
            startStopCall = null
            flutterBleCentralManager?.pendingResultForPermissionResult = null
          } else {
            flutterBleCentralManager?.pendingResultForPermissionResult?.success(State.Granted.ordinal)
          }
        } else {
          flutterBleCentralManager?.pendingResultForPermissionResult?.success(State.PermanentlyDenied.ordinal)
        }
        flutterBleCentralManager?.pendingResultForPermissionResult = null
      }
    }

    return true
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addRequestPermissionsResultListener(this)
    binding.addActivityResultListener { requestCode, resultCode, _ ->
      when (requestCode) {
        FlutterBleCentralManager.REQUEST_ENABLE_BT -> {
          if (flutterBleCentralManager?.pendingResultForActivityResult != null) {
            startStopCall = null
            flutterBleCentralManager!!.pendingResultForActivityResult!!.success(resultCode == Activity.RESULT_OK)
          } else if (flutterBleCentralManager?.pendingResultForPermissionResult != null) {
           if (resultCode == Activity.RESULT_OK) {
             if (startStopCall != null) {
               onMethodCall(startStopCall!!, flutterBleCentralManager!!.pendingResultForPermissionResult!!)
               startStopCall = null
               flutterBleCentralManager?.pendingResultForPermissionResult = null
             }
           } else {
             flutterBleCentralManager?.pendingResultForPermissionResult?.success(State.TurnedOff.ordinal)
           }
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
