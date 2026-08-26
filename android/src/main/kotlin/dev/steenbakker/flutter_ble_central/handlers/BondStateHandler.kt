package dev.steenbakker.flutter_ble_central.handlers

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Handles publishing bond (pairing) state changes to Flutter
 */
class BondStateHandler(binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {
    private val eventChannel: EventChannel = EventChannel(
        binding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/bond_state"
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
     * Publish a bond state change to Flutter
     *
     * @param address Device address
     * @param state Bond state (BluetoothDevice.BOND_* constants: 10=BOND_NONE, 11=BOND_BONDING, 12=BOND_BONDED)
     */
    fun publishBondState(address: String, state: Int) {
        handler.post {
            eventSink?.success(
                mapOf(
                    "address" to address,
                    "bondState" to state
                )
            )
        }
    }
}
