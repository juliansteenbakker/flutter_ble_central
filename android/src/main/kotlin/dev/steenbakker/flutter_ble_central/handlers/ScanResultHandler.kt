package dev.steenbakker.flutter_ble_central.handlers

import android.bluetooth.le.ScanResult
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.util.isNotEmpty
import androidx.core.util.size
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Handles publishing Bluetooth LE scan results from the native Android layer
 * to the Flutter side via an [EventChannel].
 *
 * Responsibilities:
 * - Convert [ScanResult] objects to `Map<String, Any?>` suitable for Flutter.
 * - Optionally publish "lightweight" scan results for improved performance.
 * - Send results through the `"dev.steenbakker.flutter_ble_central/scan_result"` channel.
 * - Log timing statistics for performance monitoring.
 *
 * **Lightweight mode** excludes certain fields (e.g., `rssi`, timestamps, bond state)
 * to reduce serialization overhead and increase throughput for fast scans.
 *
 * @param flutterPluginBinding The plugin binding used to access the Flutter binary messenger.
 */
class ScanResultHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {

    /** The current active Flutter event sink. */
    private var eventSink: EventChannel.EventSink? = null

    /** Indicates if the stream is active. */
    private var isRunning = false

    /** Whether to send lightweight scan results. */
    private var useLightweightScanResult = false

    /** Event channel used to communicate scan results to Flutter. */
    private val eventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/scan_result"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    /**
     * Enables or disables lightweight scan result mode.
     *
     * When enabled, only a minimal subset of fields is sent to Flutter.
     * This improves performance when handling a high volume of scan results.
     *
     * @param useLightweight Whether to use lightweight scan result serialization.
     */
    fun setUseLightweightScanResult(useLightweight: Boolean) {
        useLightweightScanResult = useLightweight
    }

    /**
     * Called when Flutter begins listening to the scan result event stream.
     *
     * @param arguments Optional arguments passed from Flutter.
     * @param events The event sink for sending data to Flutter.
     */
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    /**
     * Called when Flutter cancels its subscription to the scan result stream.
     *
     * @param arguments Optional arguments passed from Flutter.
     */
    override fun onCancel(arguments: Any?) {
        isRunning = false
        this.eventSink = null
    }

    /**
     * Publishes a scan result to the Flutter side.
     *
     * The result is converted to a map, then sent on the main thread
     * (required by Flutter's event channel API). Timing statistics
     * are logged for performance monitoring.
     *
     * @param scanResult The BLE scan result to be sent.
     */
    fun publish(scanResult: ScanResult) {
        val startTime = System.currentTimeMillis()
        val mapped = if (useLightweightScanResult) {
            scanResultToMapLight(scanResult)
        } else {
            scanResultToMap(scanResult)
        }

        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapped)
            val duration = System.currentTimeMillis() - startTime
            PublishTimingStats.logTime(duration)
        }
    }

    /**
     * Utility object for tracking and logging publishing performance.
     *
     * Keeps a running total of time spent publishing results and computes
     * average latency per call.
     */
    object PublishTimingStats {
        private val totalTime = AtomicLong(0)
        private val callCount = AtomicInteger(0)

        /**
         * Logs the time taken to process and publish a scan result.
         *
         * @param durationMs Duration of the publish operation in milliseconds.
         */
        fun logTime(durationMs: Long) {
            totalTime.addAndGet(durationMs)
            val count = callCount.incrementAndGet()
            val average = totalTime.get() / count
            Log.d("PublishTiming", "This call: $durationMs ms, Average: $average ms over $count calls")
        }
    }

    /**
     * Converts a full [ScanResult] into a Flutter-compatible map.
     *
     * Includes:
     * - Device information (address, name, type, bond state)
     * - Advertising record (flags, bytes, manufacturer data, service UUIDs/data)
     * - RSSI, timestamp, and connectable flag
     *
     * @param scanResult The scan result to convert.
     * @return A map suitable for sending over an event channel.
     */
    private fun scanResultToMap(scanResult: ScanResult): Map<String, Any?> {
        val device = scanResult.device
        val scanRecord = scanResult.scanRecord

        val deviceMap = mapOf(
            "address" to device.address,
            "bondState" to device.bondState,
            "name" to device.name,
            "type" to device.type
        )

        val scanRecordMap = mutableMapOf<String, Any?>().apply {
            this["advertiseFlags"] = scanRecord?.advertiseFlags
            this["bytes"] = scanRecord?.bytes
            this["deviceName"] = scanRecord?.deviceName
            this["txPowerLevel"] = scanRecord?.txPowerLevel

            scanRecord?.manufacturerSpecificData?.takeIf { it.isNotEmpty() }?.let { data ->
                val manufacturerMap = mutableMapOf<String, ByteArray>()
                for (i in 0 until data.size) {
                    manufacturerMap[data.keyAt(i).toString()] = data.valueAt(i)
                }
                this["manufacturerSpecificData"] = manufacturerMap
            }

            scanRecord?.serviceUuids?.takeIf { it.isNotEmpty() }?.let { uuids ->
                this["serviceUuids"] = uuids.map { it.toString() }
            }

            scanRecord?.serviceData?.takeIf { it.isNotEmpty() }?.let { serviceData ->
                val serviceDataMap = mutableMapOf<String, ByteArray>()
                for ((uuid, data) in serviceData) {
                    serviceDataMap[uuid.toString()] = data
                }
                this["serviceData"] = serviceDataMap
            }
        }

        val isConnectable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            scanResult.isConnectable
        } else {
            (scanRecord?.advertiseFlags ?: 0) and 0x02 == 0x02
        }

        return mapOf(
            "device" to deviceMap,
            "scanRecord" to scanRecordMap,
            "rssi" to scanResult.rssi,
            "timestampNanos" to scanResult.timestampNanos,
            "connectable" to isConnectable
        )
    }

    /**
     * Converts a [ScanResult] into a lightweight map with minimal fields.
     *
     * Includes only:
     * - Device address
     * - Manufacturer-specific data
     * - Service UUIDs
     *
     * Used to reduce payload size and improve performance for high-frequency scanning.
     *
     * @param scanResult The scan result to convert.
     * @return A simplified map.
     */
    private fun scanResultToMapLight(scanResult: ScanResult): Map<String, Any?> {
        val device = scanResult.device
        val scanRecord = scanResult.scanRecord

        val deviceMap = mapOf(
            "address" to device.address,
        )

        val scanRecordMap = mutableMapOf<String, Any?>().apply {
            scanRecord?.manufacturerSpecificData?.takeIf { it.isNotEmpty() }?.let { data ->
                val manufacturerMap = mutableMapOf<String, ByteArray>()
                for (i in 0 until data.size) {
                    manufacturerMap[data.keyAt(i).toString()] = data.valueAt(i)
                }
                this["manufacturerSpecificData"] = manufacturerMap
            }

            scanRecord?.serviceUuids?.takeIf { it.isNotEmpty() }?.let { uuids ->
                this["serviceUuids"] = uuids.map { it.toString() }
            }
        }

        return mapOf(
            "device" to deviceMap,
            "scanRecord" to scanRecordMap,
        )
    }
}
