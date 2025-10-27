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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.collections.component1
import kotlin.collections.component2
import kotlin.collections.iterator
import kotlin.concurrent.thread

class ScanResultHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var isRunning = false
    private var useLightweightScanResult = false

    private val eventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/scan_result"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    fun setUseLightweightScanResult(useLightweight: Boolean) {
        useLightweightScanResult = useLightweight
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        isRunning = false
        this.eventSink = null
    }

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

    object PublishTimingStats {
        val totalTime = AtomicLong(0)
        val callCount = AtomicInteger(0)

        fun logTime(durationMs: Long) {
            totalTime.addAndGet(durationMs)
            val count = callCount.incrementAndGet()
            val average = totalTime.get() / count
            Log.d("PublishTiming", "This call: $durationMs ms, Average: $average ms over $count calls")
        }
    }

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
