//
//  ScanResultHandler.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation

import class CoreBluetooth.CBUUID
import class CoreBluetooth.CBService
import enum CoreBluetooth.CBManagerState
import var CoreBluetooth.CBAdvertisementDataServiceDataKey
import var CoreBluetooth.CBAdvertisementDataServiceUUIDsKey
import var CoreBluetooth.CBAdvertisementDataManufacturerDataKey
import var CoreBluetooth.CBAdvertisementDataLocalNameKey

public class ScanResultHandler: NSObject, FlutterStreamHandler {
    
    private var eventSink: FlutterEventSink?
    
    private let eventChannel: FlutterEventChannel
    
    init(registrar: FlutterPluginRegistrar) {
        eventChannel = FlutterEventChannel(name: "dev.steenbakker.flutter_ble_central/scan_result",
                                               binaryMessenger: registrar.messenger())
        super.init()
        eventChannel.setStreamHandler(self)
    }
    
    func publishScanResult(advertiseData: AdvertisementData, rssi: Int) {
        if let eventSink = self.eventSink {
            let serviceData = advertiseData[CBAdvertisementDataServiceDataKey] as? ServiceData ?? [:]
            let serviceUuids = advertiseData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let manufacturerData = advertiseData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data();
//            let name = advertiseData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? String();
            
            let deviceDiscoveryMessage = [
//                "id": peripheral.identifier.uuidString,
//                $0.name = name
                "rssi": Int32(rssi),
                "serviceData": serviceData
                    .map { entry in
                        [entry.key.data: entry.value]
                    },
                "serviceUuids": serviceUuids.map { entry in
                    [entry.data]
                },
                "manufacturerSpecificData": manufacturerData
            ] as [String : Any]
            eventSink(deviceDiscoveryMessage)
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
