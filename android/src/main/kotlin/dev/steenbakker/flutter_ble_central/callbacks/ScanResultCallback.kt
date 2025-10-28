package dev.steenbakker.flutter_ble_central.callbacks

import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import dev.steenbakker.flutter_ble_central.handlers.ScanErrorHandler
import dev.steenbakker.flutter_ble_central.handlers.ScanResultHandler

/**
 * Custom [ScanCallback] implementation used to handle Bluetooth LE scan events.
 *
 * Responsibilities:
 * - Publish individual scan results to [ScanResultHandler].
 * - Publish batch scan results.
 * - Report scan errors to [ScanErrorHandler].
 *
 * This class acts as a bridge between Android's native BLE scanning API
 * and the Flutter event channels in the plugin layer.
 *
 * @property scanResultHandler Handles forwarding scan results to Flutter.
 * @property errorHandler Handles forwarding scan errors to Flutter.
 */
class ScanResultCallback(
    private val scanResultHandler: ScanResultHandler,
    private val errorHandler: ScanErrorHandler
) : ScanCallback() {

    /**
     * Called when a BLE device is found.
     *
     * @param callbackType Type of callback (e.g., all matches, first match, etc.)
     * @param result The [ScanResult] containing information about the discovered device
     */
    override fun onScanResult(callbackType: Int, result: ScanResult) {
        super.onScanResult(callbackType, result)
        scanResultHandler.publish(result)
    }

    /**
     * Called when the BLE scan fails to start or encounters an error.
     *
     * @param errorCode Error code indicating the type of failure
     * (see [ScanCallback] error codes, e.g. [ScanCallback.SCAN_FAILED_ALREADY_STARTED])
     */
    override fun onScanFailed(errorCode: Int) {
        super.onScanFailed(errorCode)
        errorHandler.publish(errorCode)
    }

    /**
     * Called when the system reports a batch of scan results.
     *
     * This happens if scan batching is enabled via [android.bluetooth.le.ScanSettings].
     *
     * @param results List of [ScanResult] objects discovered in this batch
     */
    override fun onBatchScanResults(results: List<ScanResult>) {
        super.onBatchScanResults(results)
        results.forEach {
            scanResultHandler.publish(it)
        }
    }
}
