import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler
import dev.steenbakker.flutter_ble_central.handlers.StateChangedHandler
import dev.steenbakker.flutter_ble_central.models.CentralState

class ScanResultCallback(private val stateChangedHandler: StateChangedHandler, private val scanResultHandler: ScanResultHandler, private val errorHandler: ScanErrorHandler): ScanCallback() {

    override fun onScanResult(callbackType: Int, result: ScanResult) {
        super.onScanResult(callbackType, result)
        scanResultHandler.ii++
        scanResultHandler.publishScanResult(result)
    }

    override fun onScanFailed(errorCode: Int) {
        super.onScanFailed(errorCode)
        val statusText: String
        when (errorCode) {
            SCAN_FAILED_ALREADY_STARTED -> {
                statusText = "SCAN_FAILED_ALREADY_STARTED"
                stateChangedHandler.publishCentralState(CentralState.advertising)
            }
            SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> {
                statusText = "SCAN_FAILED_APPLICATION_REGISTRATION_FAILED"
                stateChangedHandler.publishCentralState(CentralState.idle)
            }
            SCAN_FAILED_INTERNAL_ERROR -> {
                statusText = "SCAN_FAILED_INTERNAL_ERROR"
                stateChangedHandler.publishCentralState(CentralState.idle)
            }
            SCAN_FAILED_FEATURE_UNSUPPORTED -> {
                statusText = "SCAN_FAILED_FEATURE_UNSUPPORTED"
                stateChangedHandler.publishCentralState(CentralState.idle)
            }
            SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES -> {
                statusText = "SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES"
                stateChangedHandler.publishCentralState(CentralState.idle)
            }
            SCAN_FAILED_SCANNING_TOO_FREQUENTLY -> {
                statusText = "SCAN_FAILED_SCANNING_TOO_FREQUENTLY"
                stateChangedHandler.publishCentralState(CentralState.idle)
            }
            else -> {
                statusText = "UNDOCUMENTED"
                stateChangedHandler.publishCentralState(CentralState.unknown)
            }
        }
        errorHandler.publishScanError(errorCode)
//        errorHandler.publishScanResult(error)
//        result.error(errorCode.toString(), statusText, "startScanning")
    }

    override fun onBatchScanResults(results: List<ScanResult>) {
        super.onBatchScanResults(results)
        results.forEach {
            scanResultHandler.ii++
            scanResultHandler.publishScanResult(it)
        }
    }

}