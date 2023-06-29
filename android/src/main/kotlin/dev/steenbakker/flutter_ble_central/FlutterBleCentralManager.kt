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

  fun startScan(scanSettings: ScanSettings, result: MethodChannel.Result, scanCallback: ScanCallback) {
    try {
      mBluetoothLeScanner!!.startScan(null, scanSettings, scanCallback)
      result.success(State.Ready.ordinal)
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
  fun checkAndEnableBluetooth(shouldAsk: Boolean, result: MethodChannel.Result, activityBinding: ActivityPluginBinding): Boolean {
    return if (mBluetoothManager!!.adapter.isEnabled) {
      true
    } else {
      pendingResultForPermissionResult = result
      val hasPermission = requestPermission(activityBinding.activity, result)
      if (hasPermission == State.Granted) enableBluetooth(shouldAsk, result, activityBinding, false)
      false
    }
  }

  fun requestPermission(activity: Activity, result: MethodChannel.Result?): State {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      if (!hasBluetoothScanPermission(activity) || !hasBluetoothConnectPermission(activity)) {
        if (result != null) {
          pendingResultForPermissionResult = result
          ActivityCompat.requestPermissions(
            activity,
            arrayOf(
              Manifest.permission.BLUETOOTH_CONNECT,
              Manifest.permission.BLUETOOTH_SCAN
            ),
            REQUEST_PERMISSION_BT
          )
        }
        if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.BLUETOOTH_SCAN) ||
          ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.BLUETOOTH_CONNECT)) {
          Log.w("TEST", "Denied!")
          return State.Denied
        }
        Log.w("TEST", "Permanently denied!")
        return State.PermanentlyDenied
      } else {
        Log.w("TEST", "We have all permissions!")
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      if (!hasLocationCoarsePermission(activity) || !hasLocationFinePermission(activity)) {
        if (result != null) {
          pendingResultForPermissionResult = result
          ActivityCompat.requestPermissions(
            activity,
            arrayOf(
              Manifest.permission.ACCESS_FINE_LOCATION,
              Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            REQUEST_PERMISSION_BT
          )
        }
        if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION) ||
          ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION)) {
          return State.Denied
        }
        return State.PermanentlyDenied
      }
    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      if (!hasLocationCoarsePermission(activity)) {
        if (result != null) {
          pendingResultForPermissionResult = result
          ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION),
            REQUEST_PERMISSION_BT
          )
        }
        if (ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_COARSE_LOCATION)) {
          return State.Denied
        }
        return State.PermanentlyDenied
      }
    }
    return State.Granted
  }

  fun enableBluetooth(ask: Boolean, result: MethodChannel.Result?, activityBinding: ActivityPluginBinding, askForPermission: Boolean) {
    if (ask && pendingResultForActivityResult == null) {
      if (askForPermission) {
        pendingResultForPermissionResult = result
      } else {
        pendingResultForActivityResult = result
      }

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