package dev.steenbakker.flutter_ble_central

import android.Manifest
import android.app.Activity
import android.app.Application
import android.bluetooth.BluetoothAdapter
import dev.steenbakker.flutter_ble_central.callbacks.ScanResultCallback
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import dev.steenbakker.flutter_ble_central.FlutterBleCentralManager.Companion.REQUEST_ENABLE_BT
import dev.steenbakker.flutter_ble_central.FlutterBleCentralManager.Companion.REQUEST_PERMISSION_BT
import dev.steenbakker.flutter_ble_central.handlers.BondStateHandler
import dev.steenbakker.flutter_ble_central.handlers.CharacteristicValueHandler
import dev.steenbakker.flutter_ble_central.handlers.ConnectionStateHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import dev.steenbakker.flutter_ble_central.handlers.StateChangedHandler
import dev.steenbakker.flutter_ble_central.models.CentralState
import dev.steenbakker.flutter_ble_central.models.CentralBluetoothState
import dev.steenbakker.flutter_ble_central.GattConnectionManager
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

  /** Handler for broadcasting state changes to Flutter. */
  private lateinit var stateChangedHandler: StateChangedHandler

  /** Handler for reporting connection state changes to Flutter. */
  private lateinit var connectionStateHandler: ConnectionStateHandler

  /** Handler for reporting characteristic value changes to Flutter. */
  private lateinit var characteristicValueHandler: CharacteristicValueHandler

  /** Handler for reporting bond state changes to Flutter. */
  private lateinit var bondStateHandler: BondStateHandler

  /** BLE manager responsible for low-level Bluetooth operations. */
  private var flutterBleCentralManager: FlutterBleCentralManager? = null

  /** BroadcastReceiver to listen for Bluetooth state changes. */
  private val bluetoothStateReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
        val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
        onBluetoothStateChanged(state)
      }
    }
  }

  /** Lifecycle callbacks to detect when app resumes from background. */
  private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
    override fun onActivityResumed(activity: Activity) {
      // When activity resumes (e.g., coming back from settings), update state
      publishCurrentState()
    }
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
  }

  /** Flag to track if receiver is registered. */
  private var isReceiverRegistered = false

  /** GATT connection manager for handling device connections. */
  private var gattConnectionManager: GattConnectionManager? = null

  /** Plugin context (application context). */
  private var context: Context? = null

  /** Current activity binding, needed for permissions and settings. */
  private var activityBinding: ActivityPluginBinding? = null

  /** Active BLE scan callback, if scanning is ongoing. */
  private var scanCallback: ScanResultCallback? = null

  /** Handler for scheduling scan refresh timer */
  private val scanRefreshHandler = Handler(Looper.getMainLooper())

  /** Runnable for refreshing the scan every 4 minutes */
  private var scanRefreshRunnable: Runnable? = null

  /** Stored scan settings for restarting the scan */
  private var currentScanSettings: ScanSettings? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(
      flutterPluginBinding.binaryMessenger,
      "dev.steenbakker.flutter_ble_central/method"
    )
    methodChannel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext
    scanResultHandler = ScanResultHandler(flutterPluginBinding)
    scanErrorHandler = ScanErrorHandler(flutterPluginBinding)
    stateChangedHandler = StateChangedHandler(flutterPluginBinding)
    flutterBleCentralManager = FlutterBleCentralManager(flutterPluginBinding.applicationContext)

    // Register Bluetooth state receiver
    registerBluetoothReceiver()

    connectionStateHandler = ConnectionStateHandler(flutterPluginBinding)
    characteristicValueHandler = CharacteristicValueHandler(flutterPluginBinding)
    bondStateHandler = BondStateHandler(flutterPluginBinding)
    flutterBleCentralManager = FlutterBleCentralManager(flutterPluginBinding.applicationContext)
    gattConnectionManager = GattConnectionManager(
      flutterPluginBinding.applicationContext,
      connectionStateHandler,
      characteristicValueHandler,
      bondStateHandler
    )
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    // Clean up scan refresh timer
    cancelScanRefresh()
    // Unregister Bluetooth state receiver
    unregisterBluetoothReceiver()
    methodChannel.setMethodCallHandler(null)
    gattConnectionManager?.cleanup()
  }

  /**
   * Check if BLUETOOTH_CONNECT permission is granted.
   * This permission is required for Android 12+ (API 31+).
   */
  private fun hasBluetoothConnectPermission(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      return ContextCompat.checkSelfPermission(
        context!!,
        Manifest.permission.BLUETOOTH_CONNECT
      ) == PackageManager.PERMISSION_GRANTED
    }
    // For older versions, no BLUETOOTH_CONNECT permission needed
    return true
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

    when (call.method) {
      "start" -> handleStart(call, result)
      "stop" -> handleStop(result)
      "isSupported" -> handleIsSupported(result)
      "isBluetoothOn" -> handleIsBluetoothOn(result)
      "enableBluetooth" -> handleEnableBluetooth(call, result)
      "requestPermission" -> handleRequestPermission(result)
      "hasPermission" -> handleHasPermission(result)
      "openAppSettings" -> handleOpenAppSettings(result)
      "openBluetoothSettings" -> handleOpenBluetoothSettings(result)
      // Connection management
      "connect" -> handleConnect(call, result)
      "disconnect" -> handleDisconnect(call, result)
      "getConnectionState" -> handleGetConnectionState(call, result)
      // Service discovery
      "discoverServices" -> handleDiscoverServices(call, result)
      // Characteristic operations
      "readCharacteristic" -> handleReadCharacteristic(call, result)
      "writeCharacteristic" -> handleWriteCharacteristic(call, result)
      "setCharacteristicNotification" -> handleSetCharacteristicNotification(call, result)
      // Descriptor operations
      "readDescriptor" -> handleReadDescriptor(call, result)
      "writeDescriptor" -> handleWriteDescriptor(call, result)
      // Bond operations
      "createBond" -> handleCreateBond(call, result)
      "removeBond" -> handleRemoveBond(call, result)
      "getBondState" -> handleGetBondState(call, result)
      // Other operations
      "requestMtu" -> handleRequestMtu(call, result)
      "readRssi" -> handleReadRssi(call, result)
      "requestConnectionPriority" -> handleRequestConnectionPriority(call, result)
      // PHY operations
      "readPhy" -> handleReadPhy(call, result)
      "setPreferredPhy" -> handleSetPreferredPhy(call, result)
      // Reliable write operations
      "beginReliableWrite" -> handleBeginReliableWrite(call, result)
      "executeReliableWrite" -> handleExecuteReliableWrite(call, result)
      "abortReliableWrite" -> handleAbortReliableWrite(call, result)
      else -> handleNotImplemented(result)
    }
  }

  private fun handleStart(call: MethodCall, result: Result) {
    if (flutterBleCentralManager == null) {
      safeResult(result) { result.success(CentralBluetoothState.Unsupported.ordinal) }
      return
    }

    val manager = flutterBleCentralManager!!

    if (activityBinding == null) {
      result.error("No activity", "Activity is not attached", null)
      return
    }

    manager.ensureBluetoothReady(
      activityBinding!!.activity,
      onReady = {
        startScan(call, result)
      },
      onError = { state ->
        safeResult(result) { result.success(state.ordinal) }
      }
    )
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

    val enableTimingStats = (arguments["enableTimingStats"] as Boolean?) ?: true
    scanResultHandler.setEnableTimingStats(enableTimingStats)

    scanCallback = ScanResultCallback(scanResultHandler, scanErrorHandler)

    try {
      val builtSettings = scanSettings.build()
      currentScanSettings = builtSettings
      flutterBleCentralManager?.startScan(builtSettings, scanCallback!!)

      // Schedule scan refresh after 4 minutes (240,000 milliseconds)
      scheduleScanRefresh()

      safeResult(result) {
        result.success(CentralBluetoothState.Ready.ordinal)
      }
    } catch (e: Exception) {
      safeResult(result) {
        result.error("startScan", e.message, null)
      }
    }
  }

  /**
   * Schedules a scan refresh to occur after 4 minutes to prevent Android
   * from switching to opportunistic scan mode (which happens after 5 minutes).
   */
  private fun scheduleScanRefresh() {
    // Cancel any existing scheduled refresh
    cancelScanRefresh()

    scanRefreshRunnable = Runnable {
      refreshScan()
    }

    // Schedule refresh after 4 minutes (240,000 milliseconds)
    scanRefreshHandler.postDelayed(scanRefreshRunnable!!, 240000)
  }

  /**
   * Cancels the scheduled scan refresh timer.
   */
  private fun cancelScanRefresh() {
    scanRefreshRunnable?.let {
      scanRefreshHandler.removeCallbacks(it)
    }
    scanRefreshRunnable = null
  }

  /**
   * Refreshes the BLE scan by stopping and restarting it with the same settings.
   * This prevents Android from switching to opportunistic scan mode.
   */
  private fun refreshScan() {
    val callback = scanCallback
    val settings = currentScanSettings

    if (callback != null && settings != null) {
      try {
        // Stop the current scan
        flutterBleCentralManager?.stopScan(callback)

        // Restart the scan with the same settings
        flutterBleCentralManager?.startScan(settings, callback)

        // Schedule the next refresh
        scheduleScanRefresh()
      } catch (e: Exception) {
        // Log error but don't crash, the scan may have already been stopped
        android.util.Log.e("FlutterBleCentral", "Error refreshing scan: ${e.message}")
      }
    }
  }

  /**
   * Stop BLE scan if running.
   */
  private fun handleStop(result: Result) {
    // Cancel the refresh timer
    cancelScanRefresh()

    if (scanCallback != null) {
      flutterBleCentralManager?.stopScan(scanCallback!!)
      scanCallback = null
    }

    currentScanSettings = null

    safeResult(result) {
      result.success(CentralBluetoothState.Ready.ordinal)
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
        if (shouldAsk) {
          flutterBleCentralManager!!.enableBluetooth(activityBinding!!.activity) { bluetoothEnabled ->
            safeResult(result) {
              result.success(bluetoothEnabled)
            }
          }
          return
        } else {
          flutterBleCentralManager!!.enableBluetooth(activityBinding!!.activity, null)
        }
      }

      safeResult(result) {
        result.success(true)
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
   * Check if Bluetooth is currently on.
   */
  private fun handleIsBluetoothOn(result: Result) {
    val isOn = flutterBleCentralManager?.isBluetoothEnabled() ?: false
    safeResult(result) {
      result.success(isOn)
    }
  }

  /**
   * Handle connect method call
   */
  private fun handleConnect(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val autoConnect = args["autoConnect"] as? Boolean ?: false
    val timeout = args["timeout"] as? Int ?: 15

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.connect(
      context!!,
      address,
      autoConnect,
      timeout,
      onError = { error ->
        safeResult(result) {
          result.error("CONNECTION_ERROR", error, null)
        }
      }
    )

    safeResult(result) {
      result.success(null)
    }
  }

  /**
   * Register the Bluetooth state receiver.
   */
  private fun registerBluetoothReceiver() {
    if (!isReceiverRegistered && context != null) {
      val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        context!!.registerReceiver(bluetoothStateReceiver, filter, Context.RECEIVER_EXPORTED)
      } else {
        context!!.registerReceiver(bluetoothStateReceiver, filter)
      }
      isReceiverRegistered = true
    }
  }

  /**
   * Unregister the Bluetooth state receiver.
   */
  private fun unregisterBluetoothReceiver() {
    if (isReceiverRegistered && context != null) {
      try {
        context!!.unregisterReceiver(bluetoothStateReceiver)
      } catch (e: Exception) {
        // Receiver may not be registered
      }
      isReceiverRegistered = false
    }
  }

  /**
   * Called when Bluetooth state changes.
   */
  private fun onBluetoothStateChanged(state: Int) {
    val centralState = when (state) {
      BluetoothAdapter.STATE_OFF -> CentralState.poweredOff
      BluetoothAdapter.STATE_TURNING_OFF -> CentralState.poweredOff
      BluetoothAdapter.STATE_ON -> {
        val hasPermissions = context?.let {
          flutterBleCentralManager?.hasRequiredPermissions(it)
        } ?: false
        if (hasPermissions) CentralState.idle else CentralState.unauthorized
      }
      BluetoothAdapter.STATE_TURNING_ON -> return // Ignore transitional state
      else -> return
    }
    stateChangedHandler.publishState(centralState)
  }

  /**
   * Publish the current state based on Bluetooth and permission status.
   */
  private fun publishCurrentState() {
    val isBluetoothEnabled = flutterBleCentralManager?.isBluetoothEnabled() ?: false
    val centralState = if (!isBluetoothEnabled) {
      CentralState.poweredOff
    } else {
      val hasPermissions = context?.let {
        flutterBleCentralManager?.hasRequiredPermissions(it)
      } ?: false
      if (hasPermissions) CentralState.idle else CentralState.unauthorized
    }
    stateChangedHandler.publishState(centralState)
  }

  /**
   * Handle disconnect method call
   */
  private fun handleDisconnect(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.disconnect(address)
    safeResult(result) {
      result.success(null)
    }
  }

  /**
   * Handle getConnectionState method call
   */
  private fun handleGetConnectionState(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    val state = gattConnectionManager?.getConnectionState(address) ?: 0
    safeResult(result) {
      result.success(state)
    }
  }

  /**
   * Handle discoverServices method call
   */
  private fun handleDiscoverServices(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.discoverServices(
      address,
      onComplete = { services ->
        safeResult(result) {
          result.success(services)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("SERVICE_DISCOVERY_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle readCharacteristic method call
   */
  private fun handleReadCharacteristic(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val serviceUuid = args["serviceUuid"] as? String
    val characteristicUuid = args["characteristicUuid"] as? String

    if (address == null || serviceUuid == null || characteristicUuid == null) {
      result.error("INVALID_ARGUMENTS", "Address, serviceUuid, and characteristicUuid are required", null)
      return
    }

    gattConnectionManager?.readCharacteristic(
      address,
      serviceUuid,
      characteristicUuid,
      onComplete = { value ->
        safeResult(result) {
          result.success(value)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("READ_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle writeCharacteristic method call
   */
  private fun handleWriteCharacteristic(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val serviceUuid = args["serviceUuid"] as? String
    val characteristicUuid = args["characteristicUuid"] as? String
    val value = args["value"] as? ByteArray
    val withoutResponse = args["withoutResponse"] as? Boolean ?: false

    if (address == null || serviceUuid == null || characteristicUuid == null || value == null) {
      result.error("INVALID_ARGUMENTS", "Address, serviceUuid, characteristicUuid, and value are required", null)
      return
    }

    gattConnectionManager?.writeCharacteristic(
      address,
      serviceUuid,
      characteristicUuid,
      value,
      withoutResponse,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("WRITE_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle setCharacteristicNotification method call
   */
  private fun handleSetCharacteristicNotification(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val serviceUuid = args["serviceUuid"] as? String
    val characteristicUuid = args["characteristicUuid"] as? String
    val enable = args["enable"] as? Boolean ?: false

    if (address == null || serviceUuid == null || characteristicUuid == null) {
      result.error("INVALID_ARGUMENTS", "Address, serviceUuid, and characteristicUuid are required", null)
      return
    }

    gattConnectionManager?.setCharacteristicNotification(
      address,
      serviceUuid,
      characteristicUuid,
      enable,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("NOTIFICATION_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle readDescriptor method call
   */
  private fun handleReadDescriptor(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val serviceUuid = args["serviceUuid"] as? String
    val characteristicUuid = args["characteristicUuid"] as? String
    val descriptorUuid = args["descriptorUuid"] as? String

    if (address == null || serviceUuid == null || characteristicUuid == null || descriptorUuid == null) {
      result.error("INVALID_ARGUMENTS", "Address, serviceUuid, characteristicUuid, and descriptorUuid are required", null)
      return
    }

    gattConnectionManager?.readDescriptor(
      address,
      serviceUuid,
      characteristicUuid,
      descriptorUuid,
      onComplete = { value ->
        safeResult(result) {
          result.success(value)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("READ_DESCRIPTOR_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle writeDescriptor method call
   */
  private fun handleWriteDescriptor(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val serviceUuid = args["serviceUuid"] as? String
    val characteristicUuid = args["characteristicUuid"] as? String
    val descriptorUuid = args["descriptorUuid"] as? String
    val value = args["value"] as? ByteArray

    if (address == null || serviceUuid == null || characteristicUuid == null || descriptorUuid == null || value == null) {
      result.error("INVALID_ARGUMENTS", "Address, serviceUuid, characteristicUuid, descriptorUuid, and value are required", null)
      return
    }

    gattConnectionManager?.writeDescriptor(
      address,
      serviceUuid,
      characteristicUuid,
      descriptorUuid,
      value,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("WRITE_DESCRIPTOR_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle requestMtu method call
   */
  private fun handleRequestMtu(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val mtu = args["mtu"] as? Int

    if (address == null || mtu == null) {
      result.error("INVALID_ARGUMENTS", "Address and mtu are required", null)
      return
    }

    gattConnectionManager?.requestMtu(
      address,
      mtu,
      onComplete = { negotiatedMtu ->
        safeResult(result) {
          result.success(negotiatedMtu)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("MTU_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle readRssi method call
   */
  private fun handleReadRssi(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.readRssi(
      address,
      onComplete = { rssi ->
        safeResult(result) {
          result.success(rssi)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("RSSI_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle createBond method call
   */
  private fun handleCreateBond(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.createBond(
      address,
      onError = { error ->
        safeResult(result) {
          result.error("BOND_ERROR", error, null)
        }
      }
    )

    // Return success immediately, bond state changes will be published via event channel
    safeResult(result) {
      result.success(null)
    }
  }

  /**
   * Handle removeBond method call
   */
  private fun handleRemoveBond(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.removeBond(
      address,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("BOND_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle getBondState method call
   */
  private fun handleGetBondState(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    val bondState = gattConnectionManager?.getBondState(address) ?: android.bluetooth.BluetoothDevice.BOND_NONE
    safeResult(result) {
      result.success(bondState)
    }
  }

  /**
   * Handle requestConnectionPriority method call
   */
  private fun handleRequestConnectionPriority(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val priority = args["priority"] as? Int

    if (address == null || priority == null) {
      result.error("INVALID_ARGUMENTS", "Address and priority are required", null)
      return
    }

    gattConnectionManager?.requestConnectionPriority(
      address,
      priority,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("CONNECTION_PRIORITY_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle readPhy method call
   */
  private fun handleReadPhy(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.readPhy(
      address,
      onComplete = { txPhy, rxPhy ->
        safeResult(result) {
          result.success(mapOf("txPhy" to txPhy, "rxPhy" to rxPhy))
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("PHY_READ_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle setPreferredPhy method call
   */
  private fun handleSetPreferredPhy(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String
    val txPhy = args["txPhy"] as? Int
    val rxPhy = args["rxPhy"] as? Int
    val phyOptions = args["phyOptions"] as? Int ?: 0

    if (address == null || txPhy == null || rxPhy == null) {
      result.error("INVALID_ARGUMENTS", "Address, txPhy, and rxPhy are required", null)
      return
    }

    gattConnectionManager?.setPreferredPhy(
      address,
      txPhy,
      rxPhy,
      phyOptions,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("PHY_SET_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle beginReliableWrite method call
   */
  private fun handleBeginReliableWrite(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.beginReliableWrite(
      address,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("RELIABLE_WRITE_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle executeReliableWrite method call
   */
  private fun handleExecuteReliableWrite(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.executeReliableWrite(
      address,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("RELIABLE_WRITE_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle abortReliableWrite method call
   */
  private fun handleAbortReliableWrite(call: MethodCall, result: Result) {
    if (!hasBluetoothConnectPermission()) {
      result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
      return
    }

    if (call.arguments !is Map<*, *>) {
      result.error("INVALID_ARGUMENTS", "Arguments must be a map", null)
      return
    }

    val args = call.arguments as Map<*, *>
    val address = args["address"] as? String

    if (address == null) {
      result.error("INVALID_ARGUMENTS", "Address is required", null)
      return
    }

    gattConnectionManager?.abortReliableWrite(
      address,
      onComplete = {
        safeResult(result) {
          result.success(null)
        }
      },
      onError = { error ->
        safeResult(result) {
          result.error("RELIABLE_WRITE_ERROR", error, null)
        }
      }
    )
  }

  /**
   * Handle unsupported or unknown method calls.
   */
  private fun handleNotImplemented(result: Result) {
    safeResult(result) {
      result.notImplemented()
    }
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
          CentralBluetoothState.Granted
        }
        shouldShowRationale -> {
          flutterBleCentralManager?.setPermissionGranted(activity, false)
          CentralBluetoothState.Denied
        }
        else -> {
          flutterBleCentralManager?.setPermissionGranted(activity, false)
          CentralBluetoothState.PermanentlyDenied
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
    // Register lifecycle callbacks to detect when app resumes
    binding.activity.application.registerActivityLifecycleCallbacks(lifecycleCallbacks)
    // Publish initial state
    publishCurrentState()
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    cancelScanRefresh()
    flutterBleCentralManager?.permissionResultCallback?.invoke(CentralBluetoothState.Denied)
    flutterBleCentralManager?.permissionResultCallback = null
    // Unregister lifecycle callbacks
    activityBinding?.activity?.application?.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
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
    if (requestCode == REQUEST_ENABLE_BT) {
      flutterBleCentralManager?.bluetoothEnabledCallback?.invoke(resultCode == Activity.RESULT_OK)
      flutterBleCentralManager?.bluetoothEnabledCallback = null
    }
    return true
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
