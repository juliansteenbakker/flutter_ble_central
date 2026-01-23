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
 Represents the Bluetooth adapter state for the central manager.
 These values must match the Dart CentralState enum ordinals.
 */
enum CentralState: Int {
    /// Status is not (yet) determined.
    case unknown = 0

    /// BLE is not supported on this device.
    case unsupported = 1

    /// BLE usage is not authorized for this app.
    case unauthorized = 2

    /// BLE is turned off.
    case poweredOff = 3

    /// BLE is fully operating for this app.
    case idle = 4

    /// BLE is advertising data.
    case advertising = 5

    /// BLE is connected to a device.
    case connected = 6
}

/**
 `StateChangedHandler` is responsible for streaming Bluetooth adapter
 state changes (`CBManagerState`) from the iOS native layer to Flutter
 over an `EventChannel`.

 **Responsibilities:**
 - Listen for Bluetooth state changes reported by CoreBluetooth.
 - Publish current state to the Flutter layer.
 - Maintain legacy state for platforms or scenarios where it's needed.
 
 The event stream is sent over:
 `"dev.steenbakker.flutter_ble_central/ble_state_changed"`.
 */
public class StateChangedHandler: NSObject, FlutterStreamHandler {

    /// The Flutter event sink used to send state updates to Dart.
    private var eventSink: FlutterEventSink?

    /// Event channel for streaming Bluetooth state changes to Flutter.
    private let eventChannel: FlutterEventChannel

    /// Stores the last published state for new listeners.
    private var currentState: CentralState = .unknown

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
            name: "dev.steenbakker.flutter_ble_central/ble_state_changed",
            binaryMessenger: messenger
        )
        super.init()
        eventChannel.setStreamHandler(self)
    }

    /**
     Publishes the current Bluetooth adapter state to Flutter.
     Maps CBManagerState to CentralState values.

     - Parameter state: The current `CBManagerState`.
     */
    func publishPeripheralState(state: CBManagerState) {
        let centralState = mapCBManagerStateToCentralState(state)
        publishState(centralState)
    }

    /**
     Publishes a `CentralState` to Flutter.

     - Parameter state: The state to publish.
     */
    func publishState(_ state: CentralState) {
        currentState = state
        eventSink?(state.rawValue)
    }

    /**
     Maps CBManagerState to CentralState for consistent Dart enum values.
     */
    private func mapCBManagerStateToCentralState(_ state: CBManagerState) -> CentralState {
        switch state {
        case .unknown:
            return .unknown
        case .resetting:
            return .unknown
        case .unsupported:
            return .unsupported
        case .unauthorized:
            return .unauthorized
        case .poweredOff:
            return .poweredOff
        case .poweredOn:
            return .idle
        @unknown default:
            return .unknown
        }
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
        // Send current state to new listeners
        eventSink(currentState.rawValue)
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
