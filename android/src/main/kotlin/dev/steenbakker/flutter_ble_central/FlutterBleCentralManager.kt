package dev.steenbakker.flutter_ble_central

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterBleCentralManager(context: Context) {

  companion object {
    const val REQUEST_ENABLE_BT = 14
    const val REQUEST_PERMISSION_BT = 18
  }

  var mBluetoothManager: BluetoothManager? = null
  var mBluetoothLeScanner: BluetoothLeScanner? = null

  var pendingResultForActivityResult: MethodChannel.Result? = null
  var pendingResultForPermissionResult: MethodChannel.Result? = null

  init {
    mBluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
  }

  fun startScan(scanSettings: ScanSettings, result: MethodChannel.Result, scanCallback: ScanCallback) {
    try {
      mBluetoothLeScanner!!.startScan(null, scanSettings, scanCallback)
      result.success(null)
    } catch (e: Exception) {
      result.error("startScan", e.message, e)
    }
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

  /**
   * Enables bluetooth with a dialog or without.
   */
  fun checkAndEnableBluetooth(call: MethodCall, result: MethodChannel.Result, activityBinding: ActivityPluginBinding) {
    if (mBluetoothManager!!.adapter.isEnabled) {
      result.success(true)
    } else {
      pendingResultForPermissionResult = result
      val hasPermission = requestPermission(activityBinding)
      if (hasPermission) enableBluetooth(call.arguments as Boolean, result, activityBinding)
    }
  }

  fun requestPermission(activityBinding: ActivityPluginBinding): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      if (!hasBluetoothScanPermission(activityBinding.activity) || !hasBluetoothConnectPermission(activityBinding.activity)) {
        if (pendingResultForPermissionResult != null) {
          ActivityCompat.requestPermissions(
            activityBinding.activity,
            arrayOf(
              Manifest.permission.BLUETOOTH_CONNECT,
              Manifest.permission.BLUETOOTH_SCAN
            ),
            REQUEST_PERMISSION_BT
          )
        }
        return false
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      if (!hasLocationCoarsePermission(activityBinding.activity) || !hasLocationFinePermission(activityBinding.activity)) {
        if (pendingResultForPermissionResult != null) {
          ActivityCompat.requestPermissions(
            activityBinding.activity,
            arrayOf(
              Manifest.permission.ACCESS_FINE_LOCATION,
              Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            REQUEST_PERMISSION_BT
          )
        }
        return false
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      if (!hasLocationCoarsePermission(activityBinding.activity)) {
        if (pendingResultForPermissionResult != null) {
          ActivityCompat.requestPermissions(
            activityBinding.activity,
            arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION),
            REQUEST_PERMISSION_BT
          )
        }
        return false
      }
    }
    return true
  }

  fun enableBluetooth(ask: Boolean, result: MethodChannel.Result?, activityBinding: ActivityPluginBinding) {
    if (ask && pendingResultForActivityResult == null) {
      pendingResultForActivityResult = result
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
}