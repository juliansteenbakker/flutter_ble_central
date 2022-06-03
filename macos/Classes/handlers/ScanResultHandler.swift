//
//  ScanResultHandler.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation
import FlutterMacOS

import class CoreBluetooth.CBUUID
import class CoreBluetooth.CBService
import enum CoreBluetooth.CBManagerState
import var CoreBluetooth.CBAdvertisementDataServiceDataKey
import var CoreBluetooth.CBAdvertisementDataServiceUUIDsKey
import var CoreBluetooth.CBAdvertisementDataManufacturerDataKey
import var CoreBluetooth.CBAdvertisementDataLocalNameKey
import var CoreBluetooth.CBAdvertisementDataOverflowServiceUUIDsKey
import var CoreBluetooth.CBAdvertisementDataTxPowerLevelKey
import var CoreBluetooth.CBAdvertisementDataIsConnectable
import var CoreBluetooth.CBAdvertisementDataSolicitedServiceUUIDsKey
import CoreBluetooth

public class ScanResultHandler: NSObject, FlutterStreamHandler {
    
    private var eventSink: FlutterEventSink?
    
    private let eventChannel: FlutterEventChannel
    
    init(registrar: FlutterPluginRegistrar) {
        eventChannel = FlutterEventChannel(name: "dev.steenbakker.flutter_ble_central/scan_result",
                                           binaryMessenger: registrar.messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }
    
    func publishScanResult(advertiseData: AdvertisementData, rssi: Int, peripheral: CBPeripheral) {
//        let num = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber
//        var connectable = false
//        if num != nil {
//            connectable = num!.boolValue
//        }
        
        if let eventSink = self.eventSink {
            let localName = advertiseData[CBAdvertisementDataLocalNameKey] as? String
            let manufacturerData = advertiseData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data();
            let serviceData = advertiseData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
            
            let txPowerLevel = advertiseData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber
            let isConnectable = advertiseData[CBAdvertisementDataIsConnectable] as? Bool
            
            
            let serviceUUIDs = (advertiseData[CBAdvertisementDataServiceUUIDsKey] as? [AnyObject])?.map({ CBUUID in
                CBUUID.uuidString
            })
            
            let overflowServiceUUIDs = (advertiseData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?.map({ CBUUID in
                CBUUID.uuidString
            })
            
            let solicitedServiceUUIDs = (advertiseData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID])?.map({ CBUUID in
                CBUUID.uuidString
            })
            
            let deviceDiscoveryMessage = [
                "deviceName": localName,
                "manufacturerSpecificData": manufacturerData,
//                "serviceData": serviceData.map(),
                "serviceUuids": serviceUUIDs,
                "overflowServiceUUIDs": overflowServiceUUIDs,
//                "txPower": Int32(txPowerLevel),
                "connectable": isConnectable,
                "serviceSolicitationUuids": solicitedServiceUUIDs,
                "address": peripheral.identifier.uuidString,
                "rssi": Int32(rssi)
//                "connectable": connectable
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
