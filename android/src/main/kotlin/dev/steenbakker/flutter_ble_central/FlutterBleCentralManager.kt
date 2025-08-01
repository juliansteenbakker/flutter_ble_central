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
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import dev.steenbakker.flutter_ble_central.models.State
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

class FlutterBleCentralManager(context: Context) {

  companion object {
    const val REQUEST_ENABLE_BT = 14
    const val REQUEST_PERMISSION_BT = 18
  }

  var mBluetoothManager: BluetoothManager? = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
  var mBluetoothLeScanner: BluetoothLeScanner? = null

  var pendingResultForActivityResult: MethodChannel.Result? = null
  var pendingResultForPermissionResult: MethodChannel.Result? = null
  var permissionResultCallback: ((Boolean) -> Unit)? = null


  fun startScan(scanSettings: ScanSettings, scanCallback: ScanCallback) {
    mBluetoothLeScanner!!.startScan(null, scanSettings, scanCallback)
  }

  fun stopScan(scanCallback: ScanCallback) {
    mBluetoothLeScanner?.stopScan(scanCallback)
  }

  // Permissions for Bluetooth API > 31
  @RequiresApi(Build.VERSION_CODES.S)
  private fun hasBluetoothScanPermission(context: Context): Boolean {
    return (context.checkSelfPermission(
      Manifest.permission.BLUETOOTH_SCAN
    )
            == PackageManager.PERMISSION_GRANTED)
  }

  @RequiresApi(Build.VERSION_CODES.S)
  private fun hasBluetoothConnectPermission(context: Context): Boolean {
    return (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            == PackageManager.PERMISSION_GRANTED)
  }

  @RequiresApi(Build.VERSION_CODES.M)
  private fun hasLocationFinePermission(context: Context): Boolean {
    return (context.checkSelfPermission(
      Manifest.permission.ACCESS_FINE_LOCATION
    )
            == PackageManager.PERMISSION_GRANTED)
  }

  @RequiresApi(Build.VERSION_CODES.M)
  private fun hasLocationCoarsePermission(context: Context): Boolean {
    return (context.checkSelfPermission(
      Manifest.permission.ACCESS_COARSE_LOCATION
    )
            == PackageManager.PERMISSION_GRANTED)
  }


  fun enableBluetoothProcedure(activity: Activity) {
    if (isBluetoothEnabled()) return

    var permissions = getMissingPermissions(activity)

    if (!permissions.isEmpty()) {
      requestPermission(permissions)
      return;
    }
  }

  /**
   * Enables bluetooth with a dialog or without, and by checking permissions first.
   */
  fun checkAndEnableBluetooth(shouldAsk: Boolean): Boolean {
    return if (mBluetoothManager!!.adapter.isEnabled) {
      true
    } else {
      pendingResultForPermissionResult = result
      val hasPermission = requestPermission(activityBinding.activity, result)
      if (hasPermission == State.Granted) enableBluetooth(shouldAsk, result, activityBinding, false)
      false
    }
  }

  fun isBluetoothEnabled(): Boolean {
    return mBluetoothManager!!.adapter.isEnabled;
  }

  fun askAndEnableBluetooth(activityBinding: ActivityPluginBinding) {
    ActivityCompat.startActivityForResult(
      activityBinding.activity,
      Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
      REQUEST_ENABLE_BT,
      null
    )
  }

  fun enableBluetooth(ask: Boolean, activityBinding: ActivityPluginBinding) {
    if (ask && pendingResultForActivityResult == null) {
      ActivityCompat.startActivityForResult(
        activityBinding.activity,
        Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
        REQUEST_ENABLE_BT,
        null
      )
    } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU){
      @Suppress("DEPRECATION")
      mBluetoothManager!!.adapter.enable()
    }
  }

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


  fun requestPermission(
    activity: Activity,
    permissions: List<String>
  ) {
    // Request permissions asynchronously
    ActivityCompat.requestPermissions(
      activity,
      permissions.toTypedArray(),
      REQUEST_PERMISSION_BT
    )
  }


  fun requestPermission(activity: Activity, onPermissionReceived: (Boolean) -> Unit): State {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      if (!hasBluetoothScanPermission(activity) || !hasBluetoothConnectPermission(activity)) {
        permissionResultCallback = onPermissionReceived
        ActivityCompat.requestPermissions(
          activity,
          arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN
          ),
          REQUEST_PERMISSION_BT
        )
        if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.BLUETOOTH_SCAN) ||
          ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.BLUETOOTH_CONNECT)) {
          return State.Denied
        }
        return State.PermanentlyDenied
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      if (!hasLocationCoarsePermission(activity) || !hasLocationFinePermission(activity)) {
          permissionResultCallback = onPermissionReceived
          ActivityCompat.requestPermissions(
            activity,
            arrayOf(
              Manifest.permission.ACCESS_FINE_LOCATION,
              Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            REQUEST_PERMISSION_BT
          )
        if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION) ||
          ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION)) {
          return State.Denied
        }
        return State.PermanentlyDenied
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      if (!hasLocationCoarsePermission(activity)) {
          permissionResultCallback = onPermissionReceived
          ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION),
            REQUEST_PERMISSION_BT
          )
        if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION)) {
          return State.Denied
        }
        return State.PermanentlyDenied
      }
    }
    return State.Granted
  }
}