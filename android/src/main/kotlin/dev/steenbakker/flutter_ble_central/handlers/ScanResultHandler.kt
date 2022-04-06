package dev.steenbakker.flutter_ble_central.handlers

import android.bluetooth.le.ScanResult
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import java.util.concurrent.Executors


class ScanResultHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private val tag: String = "BLE Peripheral state "

    private var eventSink: EventChannel.EventSink? = null

    private val eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "dev.steenbakker.flutter_ble_central/scan_result"
    )

    private val executeBtDeviceSending = Executors.newSingleThreadExecutor()

    init {
        eventChannel.setStreamHandler(this)
    }

    private fun scanResultToMap(scanResult: ScanResult): MutableMap<*, *> {
        val deviceMap: MutableMap<String, Any> = HashMap()

//            if (scanResult.scanRecord != null) {
        val scanRecordMap: MutableMap<String, Any?> = HashMap()
        scanRecordMap["advertiseFlags"] = scanResult.scanRecord?.advertiseFlags
        scanRecordMap["bytes"] = scanResult.scanRecord?.bytes
        scanRecordMap["deviceName"] = scanResult.scanRecord?.deviceName
//        scanRecordMap["manufacturerSpecificData"] = scanResult.scanRecord?.manufacturerSpecificData
        if (scanResult.scanRecord?.manufacturerSpecificData != null) {
            val manufacturerSpecificDataMap: MutableMap<String, Any> = HashMap()
            for (i in 0 until scanResult.scanRecord?.manufacturerSpecificData!!.size()) {
                val key: Int = scanResult.scanRecord?.manufacturerSpecificData!!.keyAt(i)
                val obj: ByteArray = scanResult.scanRecord?.manufacturerSpecificData!!.get(key)
                manufacturerSpecificDataMap["$key"] = obj
            }
            scanRecordMap["manufacturerSpecificData"] = manufacturerSpecificDataMap
        }


        scanRecordMap["serviceData"] = scanResult.scanRecord?.serviceData
//                scanRecordMap["serviceSolicitationUuids"] = scanResult.scanRecord!!.serviceSolicitationUuids
        scanRecordMap["serviceUuids"] = scanResult.scanRecord?.serviceUuids
        scanRecordMap["txPowerLevel"] = scanResult.scanRecord?.txPowerLevel
//            }


        val scanResultMap: MutableMap<String, Any> = HashMap()
        scanResultMap["scanRecord"] = scanRecordMap
        scanResultMap["rssi"] = scanResult.rssi
        scanResultMap["timestampNanos"] = scanResult.timestampNanos

//
//            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//            }
        return scanResultMap
    }

    var i = 0
    fun publishScanResult(scanResult: ScanResult) {
//        Log.d("BLE", "SCAN RESULT $i")
        executeBtDeviceSending.execute {
            val scanResultMap = scanResultToMap(scanResult)
//            val scanResultSTring = scanResultMap.toString();
            val json = JSONObject(scanResultMap)
            val string = json.toString();
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(string)
            }
        }

//        Thread {
//            // a potentially time consuming task
//
//
//        }.start()

//        Handler(Looper.getMainLooper()).post {
//
//            i++
//            eventSink?.success("$i")
//
////            Log.d("BLE", "SCAN RESULT $i $test")
//        }
    }

    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
    }

    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}