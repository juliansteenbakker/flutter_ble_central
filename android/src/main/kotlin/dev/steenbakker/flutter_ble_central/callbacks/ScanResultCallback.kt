package dev.steenbakker.flutter_ble_central.callbacks

import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler

class ScanResultCallback(
    private val scanResultHandler: ScanResultHandler,
    private val errorHandler: ScanErrorHandler
): ScanCallback() {

    override fun onScanResult(callbackType: Int, result: ScanResult) {
        super.onScanResult(callbackType, result)
        scanResultHandler.ii++
        scanResultHandler.publishScanResult(result)
    }

    override fun onScanFailed(errorCode: Int) {
        super.onScanFailed(errorCode)
        errorHandler.publishScanError(errorCode)
    }

    override fun onBatchScanResults(results: List<ScanResult>) {
        super.onBatchScanResults(results)
        results.forEach {
            scanResultHandler.ii++
            scanResultHandler.publishScanResult(it)
        }
    }
}
