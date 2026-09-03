package dev.steenbakker.flutter_ble_central

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import dev.steenbakker.flutter_ble_central.models.CentralBluetoothState
import androidx.core.content.edit

/**
 * Manager class that handles Bluetooth LE scanning and permission handling
 * for Flutter BLE Central plugin.
 *
 * This class abstracts:
 * - Starting and stopping BLE scans
 * - Enabling Bluetooth
 * - Checking and requesting runtime permissions
 * - Managing permission persistence state
 *
 * @param context The application or activity context
 */
class FlutterBleCentralManager(context: Context) {

  companion object {
    /** Request code used when enabling Bluetooth via system dialog */
    const val REQUEST_ENABLE_BT = 14

    /** Request code used when requesting Bluetooth permissions */
    const val REQUEST_PERMISSION_BT = 18
  }

  /** Bluetooth manager reference */
  var mBluetoothManager: BluetoothManager? = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

  /** Bluetooth LE scanner instance (obtained from Bluetooth adapter) */
  var mBluetoothLeScanner: BluetoothLeScanner? = mBluetoothManager?.adapter?.bluetoothLeScanner

  /** Callback invoked after permission request result */
  var permissionResultCallback: ((CentralBluetoothState) -> Unit)? = null

  /** Callback invoked after enable bluetooth request */
  var bluetoothEnabledCallback: ((Boolean) -> Unit)? = null

  /**
   * Start scanning for nearby Bluetooth LE devices.
   *
   * @param scanSettings The scan configuration
   * @param scanCallback Callback that receives scan results
   *
   * @throws NullPointerException if [mBluetoothLeScanner] is null
   */
  fun startScan(
    filters: List<ScanFilter>?,
    scanSettings: ScanSettings,
    scanCallback: ScanCallback
  ) {
    // Null rather than an empty list: an empty list of filters matches nothing,
    // where null means everything, which is what no filter should mean.
    mBluetoothLeScanner!!.startScan(filters?.takeIf { it.isNotEmpty() }, scanSettings, scanCallback)
  }

  /**
   * Stop scanning for Bluetooth LE devices.
   *
   * @param scanCallback The callback previously used for scanning
   */
  fun stopScan(scanCallback: ScanCallback) {
    mBluetoothLeScanner?.stopScan(scanCallback)
  }

  /**
   * Checks if the app has Bluetooth scan permission (Android 12+).
   */
  @RequiresApi(Build.VERSION_CODES.S)
  private fun hasBluetoothScanPermission(context: Context): Boolean {
    return (context.checkSelfPermission(
      Manifest.permission.BLUETOOTH_SCAN
    ) == PackageManager.PERMISSION_GRANTED)
  }

  /**
   * Checks if the app has Bluetooth connect permission (Android 12+).
   */
  @RequiresApi(Build.VERSION_CODES.S)
  private fun hasBluetoothConnectPermission(context: Context): Boolean {
    return (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            == PackageManager.PERMISSION_GRANTED)
  }

  /**
   * Checks if the app has fine location permission (Android 6+).
   */
  @RequiresApi(Build.VERSION_CODES.M)
  private fun hasLocationFinePermission(context: Context): Boolean {
    return (context.checkSelfPermission(
      Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED)
  }

  /**
   * Checks if the app has coarse location permission (Android 6+).
   */
  @RequiresApi(Build.VERSION_CODES.M)
  private fun hasLocationCoarsePermission(context: Context): Boolean {
    return (context.checkSelfPermission(
      Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED)
  }

  /**
   * Checks whether Bluetooth is currently enabled.
   *
   * @return `true` if enabled, `false` otherwise
   */
  fun isBluetoothEnabled(): Boolean {
    return mBluetoothManager?.adapter?.isEnabled ?: false
  }

  /**
   * Simple check if required permissions are granted (without rationale check).
   * Can be used with just Context, doesn't require Activity.
   */
  fun hasRequiredPermissions(context: Context): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      hasBluetoothScanPermission(context) && hasBluetoothConnectPermission(context)
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      hasLocationCoarsePermission(context) && hasLocationFinePermission(context)
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      hasLocationCoarsePermission(context)
    } else {
      true // Permissions not required on older versions
    }
  }

  /**
   * Attempts to enable Bluetooth on the device.
   *
   * If [callback] is not null, shows the system dialog to request user approval.
   * If [callback] is null and the Android version is below Tiramisu, enables Bluetooth programmatically.
   *
   * @param activity Activity to use for launching the enable dialog
   * @param callback Response on intent to enable bluetooth (pre-Android 13)
   */
  fun enableBluetooth(activity: Activity, callback: ((Boolean) -> Unit)?) {
    if (callback != null) {
      bluetoothEnabledCallback = callback
      ActivityCompat.startActivityForResult(
        activity,
        Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
        REQUEST_ENABLE_BT,
        null
      )
    } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      @Suppress("DEPRECATION")
      mBluetoothManager!!.adapter.enable()
    }
  }

  /**
   * Returns a list of missing permissions depending on the Android version.
   *
   * @param activity The activity to check permissions against
   * @return List of permission strings that are not currently granted
   */
  fun getMissingPermissions(activity: Activity): List<String> {
    val missingPermissions = mutableListOf<String>()

    when {
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
        if (!hasBluetoothScanPermission(activity)) {
          missingPermissions.add(Manifest.permission.BLUETOOTH_SCAN)
        }
        if (!hasBluetoothConnectPermission(activity)) {
          missingPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
      }

      Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
        if (!hasLocationFinePermission(activity)) {
          missingPermissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (!hasLocationCoarsePermission(activity)) {
          missingPermissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
      }

      Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
        if (!hasLocationCoarsePermission(activity)) {
          missingPermissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
      }
    }

    return missingPermissions
  }

  /**
   * Checks and optionally requests missing Bluetooth-related permissions.
   *
   * @param activity The activity to request permissions from
   * @param callback Optional callback for async permission result.
   * If `null`, the method just returns the current [CentralBluetoothState].
   *
   * @return Current [CentralBluetoothState] if no request is needed, or `null` if a request was initiated.
   */
  fun requestPermission(activity: Activity, callback: ((CentralBluetoothState) -> Unit)?): CentralBluetoothState? {
    val missingPermissions = getMissingPermissions(activity)

    // No missing permissions
    if (missingPermissions.isEmpty()) {
      setPermissionGranted(activity, true)
      return CentralBluetoothState.Granted
    }

    val previouslyRequested = getPermissionRequested(activity)
    val previouslyGranted = getPermissionGranted(activity)

    val shouldShowRationale = missingPermissions.any { permission ->
      ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)
    }

    val isRevoked = previouslyGranted && missingPermissions.isNotEmpty()

    // Just checking status
    if (callback == null) {
      return when {
        isRevoked -> CentralBluetoothState.Denied
        shouldShowRationale -> CentralBluetoothState.Denied
        !previouslyRequested -> CentralBluetoothState.Denied
        else -> CentralBluetoothState.PermanentlyDenied
      }
    }

    // Request permission
    permissionResultCallback = callback
    setPermissionRequested(activity, true)
    ActivityCompat.requestPermissions(
      activity,
      missingPermissions.toTypedArray(),
      REQUEST_PERMISSION_BT
    )

    return null
  }

  /**
   * Returns the current Bluetooth adapter state as a [CentralBluetoothState] enum.
   *
   * @return [CentralBluetoothState.Unsupported] if adapter is null,
   * [CentralBluetoothState.TurnedOff] if disabled, [CentralBluetoothState.Ready] if enabled.
   */
  fun getBluetoothState(): CentralBluetoothState {
    val adapter = mBluetoothManager?.adapter
    return if (adapter == null) CentralBluetoothState.Unsupported
    else if (!adapter.isEnabled) CentralBluetoothState.TurnedOff
    else CentralBluetoothState.Ready
  }

  /**
   * Attempts to enable Bluetooth without an activity to ask through.
   *
   * Only the programmatic path is available here, which Android 13 removed, so from
   * a service on Tiramisu and above the adapter has to already be on.
   *
   * @return Whether Bluetooth is on now.
   */
  fun enableBluetooth(): Boolean {
    if (isBluetoothEnabled()) return true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return false
    @Suppress("DEPRECATION")
    mBluetoothManager?.adapter?.enable()
    return isBluetoothEnabled()
  }

  /**
   * Ensures Bluetooth is ready without an activity to ask through, which is the
   * position a foreground service or any other background isolate is in.
   *
   * Nothing can be asked for here: a service cannot show the permission dialog or
   * the enable-Bluetooth dialog, so what is already granted and already on is all
   * there is. Scanning and connecting themselves need no activity, so a service
   * started from a screen which took care of permissions can run on its own.
   */
  fun ensureBluetoothReady(
    context: Context,
    onReady: () -> Unit,
    onError: (CentralBluetoothState) -> Unit
  ) {
    if (getBluetoothState() == CentralBluetoothState.Unsupported) {
      onError(CentralBluetoothState.Unsupported)
      return
    }

    // Nothing to fall back on: without an activity the permissions cannot be asked
    // for, only reported.
    if (!hasRequiredPermissions(context)) {
      onError(CentralBluetoothState.Denied)
      return
    }

    if (!enableBluetooth()) {
      onError(CentralBluetoothState.TurnedOff)
      return
    }

    onReady()
  }

  /**
   * Ensures Bluetooth is ready before performing BLE operations.
   *
   * - Checks adapter support
   * - Requests permissions if needed
   * - Enables Bluetooth if disabled
   *
   * @param activity The activity context
   * @param onReady Callback executed if Bluetooth is ready
   * @param onError Callback executed with the error [CentralBluetoothState]
   */
  fun ensureBluetoothReady(
    activity: Activity,
    onReady: () -> Unit,
    onError: (CentralBluetoothState) -> Unit
  ) {
    if (getBluetoothState() == CentralBluetoothState.Unsupported) {
      onError(CentralBluetoothState.Unsupported)
      return
    }

    val permissionState = requestPermission(activity) { permState ->
      if (permState == CentralBluetoothState.Granted) {
        if (!isBluetoothEnabled()) {
          enableBluetooth(activity) { bluetoothEnabled ->
            if (bluetoothEnabled) {
              onReady()
            } else {
              onError(CentralBluetoothState.TurnedOff)
            }
          }
        } else {
          onReady()
        }
      } else {
        onError(permState)
      }
    }

    if (permissionState == CentralBluetoothState.Granted) {
      if (!isBluetoothEnabled()) {
        enableBluetooth(activity) { bluetoothEnabled ->
          if (bluetoothEnabled) {
            onReady()
          } else {
            onError(CentralBluetoothState.TurnedOff)
          }
        }
      } else {
        onReady()
      }
    }
  }

  /**
   * Persist the permission granted flag in SharedPreferences.
   */
  fun setPermissionGranted(context: Context, granted: Boolean) {
    val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
    prefs.edit { putBoolean("permission_granted", granted) }
  }

  /**
   * Persist the permission requested flag in SharedPreferences.
   */
  fun setPermissionRequested(context: Context, granted: Boolean) {
    val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
    prefs.edit { putBoolean("permission_requested", granted) }
  }

  /**
   * Returns whether permission has been granted previously.
   */
  fun getPermissionGranted(context: Context): Boolean {
    val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
    return prefs.getBoolean("permission_granted", false)
  }

  /**
   * Returns whether permission has been requested previously.
   */
  fun getPermissionRequested(context: Context): Boolean {
    val prefs = context.getSharedPreferences("flutter_ble_central", Context.MODE_PRIVATE)
    return prefs.getBoolean("permission_requested", false)
  }
}
