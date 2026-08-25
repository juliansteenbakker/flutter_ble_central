//
//  ConnectionStateHandler.swift
//  flutter_ble_central
//

import Foundation

#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/**
 Publishes changes in the link to a peripheral.

 The state values are the indexes of Dart's `GattConnectionState`, which is what
 the Android side sends too, so both platforms report the same numbers.

 Event channel name: `dev.steenbakker.flutter_ble_central/connection_state`
 */
final class ConnectionStateHandler: NSObject, FlutterStreamHandler {

    /// The indexes of Dart's `GattConnectionState`.
    enum State: Int {
        case disconnected = 0
        case connecting = 1
        case connected = 2
        case disconnecting = 3
    }

    private var eventSink: FlutterEventSink?

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let channel = FlutterEventChannel(
            name: "dev.steenbakker.flutter_ble_central/connection_state",
            binaryMessenger: messenger
        )
        channel.setStreamHandler(self)
    }

    func publish(address: String, state: State) {
        DispatchQueue.main.async {
            self.eventSink?(["address": address, "state": state.rawValue])
        }
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
