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


public class StateChangedHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    var legacyState: CBManagerState = CBManagerState.unknown

    private let eventChannel: FlutterEventChannel

    init(registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
        eventChannel = FlutterEventChannel(name: "dev.steenbakker.flutter_ble_peripheral/ble_state_changed",
                                           binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }

    func publishPeripheralState(state: CBManagerState) {
        if let eventSink = self.eventSink {
            eventSink(state.rawValue)
        }
    }
    
    func publishLegacyPeripheralState(state: CBManagerState) {
        self.legacyState = state
        if let eventSink = self.eventSink {
            eventSink(state.rawValue)
        }
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
