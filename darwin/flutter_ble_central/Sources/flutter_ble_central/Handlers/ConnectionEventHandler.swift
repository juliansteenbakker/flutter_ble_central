//
//  ConnectionEventHandler.swift
//  flutter_ble_central
//

import Foundation
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/**
 Streams one kind of connection event to Flutter.

 The three connection streams — connection state, characteristic values and bond
 state — differ only in their channel name and their payload, so they share this.

 `onListen` and `onCancel` arrive on the platform thread, and every publish is
 made from the platform thread too, so the sink needs no lock of its own.
 */
final class ConnectionEventHandler: NSObject, FlutterStreamHandler {

    /// The event channel this handler publishes on.
    private let eventChannel: FlutterEventChannel

    /// Set while Flutter is listening. Read and written on the platform thread.
    private var eventSink: FlutterEventSink?

    /// Called when Flutter starts listening, for a stream whose events describe a
    /// state the listener may have missed. Set by the plugin where that applies.
    var onSubscribe: (() -> Void)?

    init(registrar: FlutterPluginRegistrar, name: String) {
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
        eventChannel = FlutterEventChannel(name: name, binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }

    /**
     Hands one event to Flutter, on the platform thread.

     Dropped when nobody is listening, the way a stream nobody subscribed to is.

     - Parameter event: The payload to publish.
     */
    func publish(_ event: [String: Any]) {
        if Thread.isMainThread {
            eventSink?(event)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(event)
            }
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(
        withArguments arguments: Any?,
        eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = eventSink
        onSubscribe?()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
