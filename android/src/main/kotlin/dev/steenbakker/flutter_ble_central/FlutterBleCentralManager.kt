package dev.steenbakker.flutter_ble_central

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import android.util.SparseArray
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
      if (bluetoothAdapter.bluetoothLeScanner == null) {
//        throw PeripheralException(PeripheralState.unsupported)
      } else {
        mBluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
      }
    }
  }

  fun startScan(scanSettings: ScanSettings, result: MethodChannel.Result) {
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
//    startDuplicateDetection()
    try {
      mBluetoothLeScanner!!.startScan(null, scanSettings, scanCallback )
    result.success(null)
    } catch (e: Exception) {
      result.error("startScan", e.message, e)
    }
  }

  fun stopScan() {
    stopDuplicateDetection()
    mBluetoothLeScanner?.stopScan(scanCallback)
  }

  private val scope = MainScope() // could also use an other scope such as viewModelScope if available
  var job: Job? = null

  // TODO: Check if duplicate detection is neccessary
  private fun startDuplicateDetection() {
    stopDuplicateDetection()
    job = scope.launch {
      while(true) {
        byteArray.clear()
        delay(5000)
      }
    }
  }

  val byteArray = mutableListOf<ByteArray>()

  private fun stopDuplicateDetection() {
    job?.cancel()
    job = null
  }

  private val scanCallback = object : ScanCallback() {
    override fun onScanResult(callbackType: Int, result: ScanResult) {
      super.onScanResult(callbackType, result)
      scanResultHandler.ii++
//      byteArray.add(manuData)
      scanResultHandler.publishScanResult(result)

    }

    override fun onBatchScanResults(results: List<ScanResult>) {
      super.onBatchScanResults(results)
    }
  }
}