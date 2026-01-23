package dev.steenbakker.flutter_ble_central.handlers

import android.os.Handler
import android.os.Looper
import dev.steenbakker.flutter_ble_central.models.CentralState
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

class StateChangedHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private val tag: String = "BLE Central state "

    private var eventSink: EventChannel.EventSink? = null

    var state = CentralState.unknown

    private val eventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/ble_state_changed"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    fun publishState(state: CentralState) {
        Log.i(tag, state.name)
        this.state = state
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(state.ordinal)
        }
    }

    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
        publishState(state)
    }

    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}
