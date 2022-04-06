//
//  StateChangedHandler.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation
import CoreBluetooth


public class StateChangedHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    var legacyState: CBCentralManagerState = CBCentralManagerState.unknown

    private let eventChannel: FlutterEventChannel

    init(registrar: FlutterPluginRegistrar) {
        eventChannel = FlutterEventChannel(name: "dev.steenbakker.flutter_ble_peripheral/ble_state_changed",
                                               binaryMessenger: registrar.messenger())
        super.init()
        eventChannel.setStreamHandler(self)
    }

    @available(iOS 10.0, *)
    func publishPeripheralState(state: CBManagerState) {
        if let eventSink = self.eventSink {
            eventSink(state.rawValue)
        }
    }
    
    func publishLegacyPeripheralState(state: CBCentralManagerState) {
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
