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
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import dev.steenbakker.flutter_ble_central.handlers.StateChangedHandler
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FlutterBleCentralManager(context: Context, val scanResultHandler: ScanResultHandler, val scanErrorHandler: ScanErrorHandler, val stateChangedHandler: StateChangedHandler) {

  companion object {
    const val REQUEST_ENABLE_BT = 14
    const val REQUEST_PERMISSION_BT = 18
  }

  var mBluetoothManager: BluetoothManager? = null
  var mBluetoothLeScanner: BluetoothLeScanner? = null

  var pendingResultForActivityResult: MethodChannel.Result? = null

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
      val hasPermission = requestPermission(activityBinding, true)
      if (hasPermission) enableBluetooth(call, result, activityBinding)
    }
  }

  fun requestPermission(activityBinding: ActivityPluginBinding, request: Boolean): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      if (!hasBluetoothScanPermission(activityBinding.activity) || !hasBluetoothConnectPermission(activityBinding.activity)) {
        if(request) ActivityCompat.requestPermissions(
          activityBinding.activity,
          arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN
          ),
          REQUEST_PERMISSION_BT
        )
        return false
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      if (!hasLocationCoarsePermission(activityBinding.activity) || !hasLocationFinePermission(activityBinding.activity)) {
        if(request) ActivityCompat.requestPermissions(activityBinding.activity,
          arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
          REQUEST_PERMISSION_BT
        )
        return false
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      if (!hasLocationCoarsePermission(activityBinding.activity)) {
        if(request) ActivityCompat.requestPermissions(activityBinding.activity,
          arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION),
          REQUEST_PERMISSION_BT
        )
        return false
      }
    }
    return true
  }

  var intent: Intent? = null

  @Suppress("deprecation")
  fun enableBluetooth(call: MethodCall?, result: MethodChannel.Result?, activityBinding: ActivityPluginBinding) {
    if (call == null && intent == null|| call != null && call.arguments as Boolean && pendingResultForActivityResult == null) {
      pendingResultForActivityResult = result
      intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
      ActivityCompat.startActivityForResult(
        activityBinding.activity,
        intent!!,
        REQUEST_ENABLE_BT,
        null
      )
    } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU){
      mBluetoothManager!!.adapter.enable()
    }
  }
}