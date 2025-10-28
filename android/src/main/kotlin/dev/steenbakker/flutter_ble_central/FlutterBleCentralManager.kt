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

class FlutterBleCentralManager(context: Context) {

  companion object {
    const val REQUEST_ENABLE_BT = 14
    const val REQUEST_PERMISSION_BT = 18
  }

  var mBluetoothManager: BluetoothManager? = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
  var mBluetoothLeScanner: BluetoothLeScanner? = null

  var permissionResultCallback: ((State) -> Unit)? = null


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


  fun isBluetoothEnabled(): Boolean {
    return mBluetoothManager?.adapter?.isEnabled ?: false
  }

  fun enableBluetooth(activity: Activity, ask: Boolean) {
    if (ask) {
      ActivityCompat.startActivityForResult(
        activity,
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


  /**
   * Check permission status and request if needed
   * Returns the current permission state
   * If permissions need to be requested, will trigger the permission dialog and return State.Denied initially
   */
  fun requestPermission(activity: Activity, callback: ((State) -> Unit)?): State {
    val missingPermissions = getMissingPermissions(activity)

    if (missingPermissions.isEmpty()) {
      return State.Granted
    }

    // If callback is provided, store it and request permissions
    if (callback != null) {
      permissionResultCallback = callback
      ActivityCompat.requestPermissions(
        activity,
        missingPermissions.toTypedArray(),
        REQUEST_PERMISSION_BT
      )

      // Check if we should show rationale (user previously denied)
      val shouldShowRationale = missingPermissions.any { permission ->
        ActivityCompat.shouldShowRequestPermissionRationale(activity, permission)
      }

      return if (shouldShowRationale) State.Denied else State.PermanentlyDenied
    }

    // No callback provided, just return the state without requesting
    return State.Denied
  }
}