package dev.steenbakker.flutter_ble_central.handlers

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Handles publishing connection state changes to Flutter
 */
class ConnectionStateHandler(binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private val eventChannel: EventChannel = EventChannel(
        binding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/connection_state"
    )
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())

    init {
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Publish a connection state change to Flutter
     *
     * @param address Device address
     * @param state Connection state (BluetoothProfile constants)
     */
    fun publishConnectionState(address: String, state: Int) {
        handler.post {
            eventSink?.success(
                mapOf(
                    "address" to address,
                    "state" to state
                )
            )
        }
    }
}
