package dev.steenbakker.flutter_ble_central.handlers

import android.os.Handler
import android.os.Looper
import dev.steenbakker.flutter_ble_central.models.CentralState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

class StateChangedHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    var state = CentralState.idle

    private val eventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/ble_state_changed"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    fun publishCentralState(state: CentralState) {
        this.state = state
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(state.ordinal)
        }
    }

    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
        publishCentralState(state)
    }

    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}