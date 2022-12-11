package dev.steenbakker.flutter_ble_central.handlers

import android.bluetooth.le.ScanResult
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.util.concurrent.Executors


class ScanResultHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null

    private val eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "dev.steenbakker.flutter_ble_central/scan_result"
    )

    private val executeBtDeviceSending = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors())

    init {
        eventChannel.setStreamHandler(this)
    }

    private fun scanResultToMap(scanResult: ScanResult): MutableMap<*, *> {
        val deviceMap: MutableMap<String, Any?> = HashMap()
        deviceMap["address"] = scanResult.device.address
        deviceMap["bondState"] = scanResult.device.bondState
        deviceMap["name"] = scanResult.device.name
        deviceMap["type"] = scanResult.device.type

        val scanRecordMap: MutableMap<String, Any?> = HashMap()
        scanRecordMap["advertiseFlags"] = scanResult.scanRecord?.advertiseFlags
        scanRecordMap["bytes"] = scanResult.scanRecord?.bytes
        scanRecordMap["deviceName"] = scanResult.scanRecord?.deviceName

        scanRecordMap["manufacturerSpecificData"] = scanResult.scanRecord?.manufacturerSpecificData
        if (scanResult.scanRecord?.manufacturerSpecificData != null) {
            val manufacturerSpecificDataMap: MutableMap<String, Any> = HashMap()
            scanResult.scanRecord?.manufacturerSpecificData!!
            for (i in 0 until scanResult.scanRecord?.manufacturerSpecificData!!.size()) {
                val key: Int = scanResult.scanRecord?.manufacturerSpecificData!!.keyAt(i)
                val obj: ByteArray = scanResult.scanRecord?.manufacturerSpecificData!!.get(key)
                manufacturerSpecificDataMap["$key"] = obj
            }
            scanRecordMap["manufacturerSpecificData"] = manufacturerSpecificDataMap
        }


        scanRecordMap["serviceData"] = scanResult.scanRecord?.serviceData
        if (scanResult.scanRecord?.serviceUuids != null && scanResult.scanRecord!!.serviceUuids.isNotEmpty()) {
            val uuidList: MutableList<String> = mutableListOf()
            for (id in scanResult.scanRecord!!.serviceUuids) {
                uuidList.add(id.toString())
            }
            scanRecordMap["serviceUuids"] = uuidList
        }

        scanRecordMap["txPowerLevel"] = scanResult.scanRecord?.txPowerLevel

        val scanResultMap: MutableMap<String, Any> = HashMap()
        scanResultMap["scanRecord"] = scanRecordMap
        scanResultMap["device"] = deviceMap
        scanResultMap["rssi"] = scanResult.rssi
        scanResultMap["timestampNanos"] = scanResult.timestampNanos
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            scanResultMap["connectable"] = scanResult.isConnectable
        } else {
            val flags = scanResult.scanRecord!!.advertiseFlags
            scanResultMap["connectable"] = flags and 2 == 2
        }

        return scanResultMap
    }

    fun publishScanResult(scanResult: ScanResult) {
        executeBtDeviceSending.execute {
            val scanResultMap = scanResultToMap(scanResult)
            val json = JSONObject(scanResultMap)
            ii--
            json.put("queue", ii)
            val string = json.toString()
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(string)
            }
        }
    }
    var ii = 0

    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
    }

    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}