package dev.steenbakker.flutter_ble_central

import dev.steenbakker.flutter_ble_central.callbacks.ScanResultCallback
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
import dev.steenbakker.flutter_ble_central.FlutterBleCentralManager.Companion.REQUEST_PERMISSION_BT
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import dev.steenbakker.flutter_ble_central.models.State
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter plugin entry point for the Flutter BLE Central library.
 *
 * Responsibilities:
 * - Manage the method channel and handle Flutter method calls.
 * - Coordinate Bluetooth LE operations through [FlutterBleCentralManager].
 * - Handle Android runtime permissions and activity results.
 * - Interface with Flutter handlers for scan results, errors, and state changes.
 */
class FlutterBleCentralPlugin :
  FlutterPlugin,
  MethodCallHandler,
  ActivityAware,
  PluginRegistry.RequestPermissionsResultListener,
  PluginRegistry.ActivityResultListener {

  /** Method channel used for communication with Flutter. */
  private lateinit var methodChannel: MethodChannel

  /** Handler for broadcasting scan results to Flutter. */
  private lateinit var scanResultHandler: ScanResultHandler

  /** Handler for reporting scan errors to Flutter. */
  private lateinit var scanErrorHandler: ScanErrorHandler

  /** BLE manager responsible for low-level Bluetooth operations. */
  private var flutterBleCentralManager: FlutterBleCentralManager? = null

  /** Plugin context (application context). */
  private var context: Context? = null

  /** Current activity binding, needed for permissions and settings. */
  private var activityBinding: ActivityPluginBinding? = null

  /** Active BLE scan callback, if scanning is ongoing. */
  private var scanCallback: ScanResultCallback? = null

  /** Cached method call for deferred start when permissions or Bluetooth state aren't ready. */
  private var startStopCall: MethodCall? = null

  /** Cached result for the deferred call. */
  private var startStopResult: Result? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(
      flutterPluginBinding.binaryMessenger,
      "dev.steenbakker.flutter_ble_central/method"
    )
    methodChannel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext
    scanResultHandler = ScanResultHandler(flutterPluginBinding)
    scanErrorHandler = ScanErrorHandler(flutterPluginBinding)
    flutterBleCentralManager = FlutterBleCentralManager(flutterPluginBinding.applicationContext)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
  }

  /**
   * Handles all incoming method calls from Flutter.
   */
  override fun onMethodCall(call: MethodCall, result: Result) {
    if (flutterBleCentralManager == null || context == null) {
      safeResult(result) {
        result.error("Not initialized", "FlutterBleCentral is not correctly initialized", null)
      }
      return
    }

    // If starting scan, ensure Bluetooth is ready
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

  /**
   * Start BLE scan with the provided settings.
   */
  private fun handleStart(call: MethodCall, result: Result) {
    startScan(call, result)
  }

  /**
   * Stop BLE scan if running.
   */
  private fun handleStop(result: Result) {
    if (scanCallback != null) {
      flutterBleCentralManager?.stopScan(scanCallback!!)
    }
    safeResult(result) {
      result.success(State.Ready.ordinal)
    }
  }

  /**
   * Check if device supports Bluetooth feature.
   */
  private fun handleIsSupported(result: Result) {
    val isSupported = context?.packageManager?.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
    safeResult(result) {
      result.success(isSupported)
    }
  }

  /**
   * Request enabling Bluetooth.
   *
   * @param call Flutter method call with `shouldAsk` argument
   * @param result Method channel result callback
   */
  private fun handleEnableBluetooth(call: MethodCall, result: Result) {
    if (activityBinding != null) {
      val shouldAsk = call.arguments as Boolean
      val isEnabled = flutterBleCentralManager!!.isBluetoothEnabled()
      if (!isEnabled) {
        flutterBleCentralManager!!.enableBluetooth(activityBinding!!.activity, shouldAsk)
      }
      safeResult(result) {
        result.success(isEnabled)
      }
    } else {
      safeResult(result) {
        result.error("No activity", "FlutterBlePeripheral is not correctly initialized", "null")
      }
    }
  }

  /**
   * Request runtime Bluetooth permissions.
   */
  private fun handleRequestPermission(result: Result) {
    val state = flutterBleCentralManager!!.requestPermission(activityBinding!!.activity) { state ->
      safeResult(result) {
        result.success(state.ordinal)
      }
    }

    // If already granted, return immediately
    if (state != null) {
      safeResult(result) {
        result.success(state.ordinal)
      }
    }
  }

  /**
   * Check if Bluetooth permissions are granted.
   */
  private fun handleHasPermission(result: Result) {
    val permission = flutterBleCentralManager!!
      .requestPermission(activityBinding!!.activity, null)!!
      .ordinal
    safeResult(result) {
      result.success(permission)
    }
  }

  /**
   * Open system app settings for this application.
   */
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

  /**
   * Open system Bluetooth settings.
   */
  private fun handleOpenBluetoothSettings(result: Result) {
    activityBinding!!.activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS), null)
    safeResult(result) {
      result.success(null)
    }
  }

  /**
   * Handle unsupported or unknown method calls.
   */
  private fun handleNotImplemented(result: Result) {
    safeResult(result) {
      result.notImplemented()
    }
  }

  /**
   * Configures and starts a BLE scan based on arguments received from Flutter.
   *
   * @throws IllegalArgumentException if arguments are not a valid map
   */
  private fun startScan(call: MethodCall, result: Result) {
    if (call.arguments !is Map<*, *>) {
      throw IllegalArgumentException("Arguments are not a map! " + call.arguments)
    }

    val arguments = call.arguments as Map<*, *>

    val scanSettings = ScanSettings.Builder()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      (arguments["legacyMode"] as Boolean?)?.let {
        scanSettings.setLegacy(it)
      }
      (arguments["phy"] as Int?)?.let {
        scanSettings.setPhy(it)
      }
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      (arguments["callbackType"] as Int?)?.let { scanSettings.setCallbackType(it) }
      (arguments["matchMode"] as Int?)?.let { scanSettings.setMatchMode(it) }
      (arguments["numOfMatches"] as Int?)?.let { scanSettings.setNumOfMatches(it) }
    }

    (arguments["reportDelay"] as Int?)?.let {
      scanSettings.setReportDelay(it.toLong())
    }
    (arguments["scanMode"] as Int?)?.let {
      scanSettings.setScanMode(it)
    }

    val useLightweightScanResult = (arguments["useLightweightScanResult"] as Boolean?) ?: false
    scanResultHandler.setUseLightweightScanResult(useLightweightScanResult)

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

  /**
   * Check Bluetooth adapter state and ensure permissions and adapter readiness.
   *
   * @return [State.Ready] if everything is OK, or another [State] if not.
   */
  private fun checkBluetoothState(result: Result): State {
    val manager = flutterBleCentralManager ?: return State.Unsupported
    if (activityBinding == null) {
      result.error("No activity", "Activity is not attached", null)
      return State.Denied
    }

    var returnedState = State.Denied
    manager.ensureBluetoothReady(
      activityBinding!!.activity,
      onReady = {
        startStopCall?.let { call ->
          startStopResult?.let { res ->
            onMethodCall(call, res)
          }
        }
        startStopCall = null
        startStopResult = null
        returnedState = State.Ready
      },
      onError = { state ->
        safeResult(result) { result.success(state.ordinal) }
        returnedState = state
      }
    )
    return returnedState
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode == REQUEST_PERMISSION_BT) {
      val activity = activityBinding!!.activity

      var hasAllPermissions = true
      var shouldShowRationale = false

      for (i in permissions.indices) {
        val grantResult = grantResults[i]
        val permission = permissions[i]
        if (grantResult == PackageManager.PERMISSION_DENIED) {
          hasAllPermissions = false
          if (ActivityCompat.shouldShowRequestPermissionRationale(
              activity,
              permission
            )
          ) {
            shouldShowRationale = true
          }
        }
      }

      val resultState = when {
        hasAllPermissions -> {
          flutterBleCentralManager?.setPermissionGranted(activity, true)
          State.Granted
        }
        shouldShowRationale -> {
          flutterBleCentralManager?.setPermissionGranted(activity, false)
          State.Denied
        }
        else -> {
          flutterBleCentralManager?.setPermissionGranted(activity, false)
          State.PermanentlyDenied
        }
      }

      flutterBleCentralManager?.permissionResultCallback?.invoke(resultState)
      flutterBleCentralManager?.permissionResultCallback = null
    }
    return true
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addRequestPermissionsResultListener(this)
    binding.addActivityResultListener(this)
    activityBinding = binding
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    flutterBleCentralManager?.permissionResultCallback?.invoke(State.Denied)
    flutterBleCentralManager?.permissionResultCallback = null
    activityBinding = null
  }

  /**
   * Handle activity result from Bluetooth enable dialog.
   */
  override fun onActivityResult(
    requestCode: Int,
    resultCode: Int,
    data: Intent?
  ): Boolean {
    if (requestCode == REQUEST_PERMISSION_BT) {
      if (resultCode == Activity.RESULT_OK) {
        // Bluetooth was enabled
        if (startStopCall != null && startStopResult != null) {
          onMethodCall(startStopCall!!, startStopResult!!)
          startStopCall = null
          startStopResult = null
        }
      }
      return true
    }
    return false
  }

  /**
   * Safely executes a [Result] callback on the main thread.
   *
   * Catches exceptions and reports them to Flutter.
   *
   * @param result The result callback to send responses to Flutter
   * @param block The action to perform
   */
  private fun safeResult(result: Result, block: () -> Unit) {
    Handler(Looper.getMainLooper()).post {
      try {
        block()
      } catch (e: Exception) {
        result.error("UNEXPECTED_ERROR", e.message, null)
      }
    }
  }
}
