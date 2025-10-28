package dev.steenbakker.flutter_ble_central.handlers

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Handles publishing Bluetooth scan errors from the native Android layer
 * to the Flutter side through a [EventChannel].
 *
 * This class is responsible for:
 * - Managing the scan error event stream.
 * - Publishing scan errors to Flutter when failures occur during scanning.
 *
 * The event stream is sent over the channel:
 * `dev.steenbakker.flutter_ble_central/scan_error`.
 *
 * Example use case:
 * - If the scan fails with an error like [android.bluetooth.le.ScanCallback.SCAN_FAILED_ALREADY_STARTED],
 *   this handler will publish that error code to Flutter.
 *
 * @param flutterPluginBinding Binding to access Flutter engine and its binary messenger.
 */
class ScanErrorHandler(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler {

    /** The active event sink for sending error events to Flutter. */
    private var eventSink: EventChannel.EventSink? = null

    /** The event channel over which scan error events are sent to Flutter. */
    private val eventChannel = EventChannel(
        flutterPluginBinding.binaryMessenger,
        "dev.steenbakker.flutter_ble_central/scan_error"
    )

    init {
        eventChannel.setStreamHandler(this)
    }

    /**
     * Publishes a scan error code to the Flutter event stream.
     *
     * This method ensures that events are dispatched on the main thread,
     * which is required by Flutter's event channel API.
     *
     * @param scanError The error code to be sent to Flutter
     * (e.g., [android.bluetooth.le.ScanCallback.SCAN_FAILED_ALREADY_STARTED]).
     */
    fun publish(scanError: Int) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(scanError)
        }
    }

    /**
     * Called when Flutter starts listening to the scan error event channel.
     *
     * @param event Optional arguments passed from Flutter when starting the stream.
     * @param eventSink The sink through which events are sent to Flutter.
     */
    override fun onListen(event: Any?, eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
    }

    /**
     * Called when Flutter cancels its subscription to the event stream.
     *
     * @param event Optional arguments passed from Flutter when canceling the stream.
     */
    override fun onCancel(event: Any?) {
        this.eventSink = null
    }
}
