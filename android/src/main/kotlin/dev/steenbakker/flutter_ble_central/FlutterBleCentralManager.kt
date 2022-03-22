package dev.steenbakker.flutter_ble_central

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.util.Log
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import io.flutter.plugin.common.MethodChannel

class FlutterBleCentralManager(context: Context, val scanResultHandler: ScanResultHandler) {

  private lateinit var mBluetoothManager: BluetoothManager
  private var mBluetoothLeScanner: BluetoothLeScanner? = null

  init {
    val bluetoothManager: BluetoothManager? =
            context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

    if (bluetoothManager == null) {
//      throw PeripheralException(PeripheralState.unsupported)
    } else {
      mBluetoothManager = bluetoothManager

      val bluetoothAdapter: BluetoothAdapter = bluetoothManager.adapter
      //&& !bluetoothAdapter.isMultipleAdvertisementSupported
      if (bluetoothAdapter.bluetoothLeScanner == null) {
        //disabled
//        throw PeripheralException(PeripheralState.unsupported)
      } else {
        mBluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
      }
    }
  }

  fun startScan(scanSettings: ScanSettings, result: MethodChannel.Result) {
    try {
//      allowDuplicates = scanSettings
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        startScan21(scanSettings)
      } else {
//        startScan18(settings)
      }
      result.success(null)
    } catch (e: Exception) {
      result.error("startScan", e.message, e)
    }
  }

  private fun startScan21(scanSettings: ScanSettings) {
//    val scanner = mBluetoothAdapter!!.bluetoothLeScanner
//            ?: throw IllegalStateException("getBluetoothLeScanner() is null. Is the Adapter on?")
//    val scanMode: Int = scanSettings.scanMode
//    val count: Int = proto.getServiceUuidsCount()
//    val filters: MutableList<ScanFilter> = ArrayList(count)
//    for (i in 0 until count) {
//      val uuid: String = proto.getServiceUuids(i)
//      val f = ScanFilter.Builder().setServiceUuid(ParcelUuid.fromString(uuid)).build()
//      filters.add(f)
//    }
    mBluetoothLeScanner!!.startScan(null, scanSettings, scanCallback )
  }

  fun stopScan() {
    mBluetoothLeScanner?.stopScan(scanCallback)
  }

  private val scanCallback = object : ScanCallback() {
    override fun onScanResult(callbackType: Int, result: ScanResult) {
      super.onScanResult(callbackType, result)

      scanResultHandler.publishScanResult(result)


//      if (!allowDuplicates && result.device != null && result.device.address != null) {
//        if (macDeviceScanned.contains(result.device.address)) {
//          return
//        }
//        macDeviceScanned.add(result.device.address)
//      }
//      val scanResult: Protos.ScanResult = ProtoMaker.from(result.device, result)
//      invokeMethodUIThread("ScanResult", scanResult.toByteArray())
    }

    override fun onBatchScanResults(results: List<ScanResult>) {
      super.onBatchScanResults(results)
    }

    override fun onScanFailed(errorCode: Int) {
      super.onScanFailed(errorCode)
    }
  }
}