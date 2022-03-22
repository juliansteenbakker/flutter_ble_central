package dev.steenbakker.flutter_ble_central.handlers

import android.bluetooth.le.ScanResult
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel


class ScanResultHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private val tag: String = "BLE Peripheral state "

    private var eventSink: EventChannel.EventSink? = null

    private val eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "dev.steenbakker.flutter_ble_central/scan_result"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    var i = 0
    fun publishScanResult(scanResult: ScanResult) {
        Handler(Looper.getMainLooper()).post {
//            var test = Gson().toJson(scanResult)
//            eventSink?.success(test)
                  i++
                Log.d("BLE", "SCAN RESULT $i")
        }
    }

    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
    }

    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}