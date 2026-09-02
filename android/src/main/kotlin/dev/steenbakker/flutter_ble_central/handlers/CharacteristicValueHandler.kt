package dev.steenbakker.flutter_ble_central.handlers

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Handles publishing characteristic value changes to Flutter
 */
class CharacteristicValueHandler(binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private val eventChannel: EventChannel = EventChannel(
        binding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/characteristic_value"
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
     * Publish a characteristic value change to Flutter
     *
     * @param address Device address
     * @param serviceUuid Service UUID
     * @param characteristicUuid Characteristic UUID
     * @param value Characteristic value
     */
    fun publishCharacteristicValue(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        value: ByteArray
    ) {
        handler.post {
            eventSink?.success(
                hashMapOf<String, Any?>(
                    "address" to address,
                    "serviceUuid" to serviceUuid,
                    "characteristicUuid" to characteristicUuid,
                    "value" to value
                )
            )
        }
    }
}
