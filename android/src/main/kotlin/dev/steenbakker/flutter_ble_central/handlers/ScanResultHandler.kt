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
import java.util.UUID
import kotlin.collections.component1
import kotlin.collections.component2
import kotlin.collections.iterator
import kotlin.concurrent.thread

class ScanResultHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var isRunning = false

    private val eventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/scan_result"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
//        startDummyEmitter()
    }

    override fun onCancel(arguments: Any?) {
        isRunning = false
        this.eventSink = null
    }

    fun publish(scanResult: ScanResult) {
        val mapped = scanResultToMap(scanResult)
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapped)
        }
    }

//    private fun scanResultToMap(id: Int): Map<String, Any?> {
//        val dummyDevice = mapOf(
//            "address" to "00:11:22:33:44:${id % 100}",
//            "bondState" to 12,
//            "name" to "DummyDevice$id",
//            "type" to 3,
//        )
//
//        val dummyScanRecord = mapOf(
//            "advertiseFlags" to 2,
//            "bytes" to ByteArray(10) { it.toByte() },
//            "deviceName" to "DummyDevice$id",
//            "txPowerLevel" to -59,
//            "manufacturerSpecificData" to mapOf("1234" to ByteArray(3) { (it + id).toByte() }),
//            "serviceUuids" to listOf(UUID.randomUUID().toString()),
//            "serviceData" to mapOf(UUID.randomUUID().toString() to ByteArray(5) { it.toByte() })
//        )
//
//        return mapOf(
//            "device" to dummyDevice,
//            "scanRecord" to dummyScanRecord,
//            "rssi" to (-60..-30).random(),
//            "timestampNanos" to System.nanoTime(),
//            "connectable" to true
//        )
//    }
//
//    private fun startDummyEmitter() {
//        isRunning = true
//        thread {
//            val handler = Handler(Looper.getMainLooper())
//            var counter = 0
//            var totalPackets = 0
//
//            while (isRunning) {
//                val batchSize = 5000
//                val packets = List(batchSize) { scanResultToMap(counter + it) }
//
//                    packets.forEach { packet ->
//                        handler.post {
//                        eventSink?.success(packet)
//                    }
//                }
//
//                counter += batchSize
//                totalPackets += batchSize
//
//                Log.i("ScanResultEmitter", "Sent $batchSize packets this second, total: $totalPackets")
//
//                Thread.sleep(1000)
//            }
//        }
//    }

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
}
