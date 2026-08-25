//
//  CharacteristicValueHandler.swift
//  flutter_ble_central
//

import Foundation

#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/**
 Publishes values a peripheral notified on a characteristic.

 Event channel name: `dev.steenbakker.flutter_ble_central/characteristic_value`
 */
final class CharacteristicValueHandler: NSObject, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let channel = FlutterEventChannel(
            name: "dev.steenbakker.flutter_ble_central/characteristic_value",
            binaryMessenger: messenger
        )
        channel.setStreamHandler(self)
    }

    func publish(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        value: Data
    ) {
        DispatchQueue.main.async {
            self.eventSink?([
                "address": address,
                "serviceUuid": serviceUuid,
                "characteristicUuid": characteristicUuid,
                "value": FlutterStandardTypedData(bytes: value),
            ])
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
