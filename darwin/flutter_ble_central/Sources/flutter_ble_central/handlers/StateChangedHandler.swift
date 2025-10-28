//
//  StateChangedHandler.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation
import CoreBluetooth

#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
#endif

/**
 `StateChangedHandler` is responsible for streaming Bluetooth adapter
 state changes (`CBManagerState`) from the iOS native layer to Flutter
 over an `EventChannel`.

 **Responsibilities:**
 - Listen for Bluetooth state changes reported by CoreBluetooth.
 - Publish current state to the Flutter layer.
 - Maintain legacy state for platforms or scenarios where it's needed.
 
 The event stream is sent over:
 `"dev.steenbakker.flutter_ble_peripheral/ble_state_changed"`.
 */
public class StateChangedHandler: NSObject, FlutterStreamHandler {

    /// The Flutter event sink used to send state updates to Dart.
    private var eventSink: FlutterEventSink?

    /// Event channel for streaming Bluetooth state changes to Flutter.
    private let eventChannel: FlutterEventChannel

    /**
     Creates a new `StateChangedHandler` and sets up its event channel.

     - Parameter registrar: The plugin registrar used to obtain a Flutter messenger.
     */
    init(registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
        eventChannel = FlutterEventChannel(
            name: "dev.steenbakker.flutter_ble_peripheral/ble_state_changed",
            binaryMessenger: messenger
        )
        super.init()
        eventChannel.setStreamHandler(self)
    }

    /**
     Publishes the current Bluetooth adapter state to Flutter.

     - Parameter state: The current `CBManagerState`.
     */
    func publishPeripheralState(state: CBManagerState) {
        eventSink?(state.rawValue)
    }

    // MARK: - FlutterStreamHandler

    /**
     Called when Flutter starts listening to the event channel.
     */
    public func onListen(
        withArguments arguments: Any?,
        eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    /**
     Called when Flutter cancels its subscription to the event channel.
     */
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
