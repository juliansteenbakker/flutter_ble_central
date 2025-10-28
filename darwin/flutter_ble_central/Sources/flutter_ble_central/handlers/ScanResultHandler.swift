//
//  ScanResultHandler.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
#endif

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
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
        eventChannel = FlutterEventChannel(name: "dev.steenbakker.flutter_ble_central/scan_result",
                                           binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }
    
    func publishScanResult(advertiseData: AdvertisementData, rssi: Int, peripheral: CBPeripheral) {
//        let num = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber
//        var connectable = false
//        if num != nil {
//            connectable = num!.boolValue
//        },
        
        if let eventSink = self.eventSink {
            let localName = advertiseData[CBAdvertisementDataLocalNameKey] as? String
            let manufacturerData = advertiseData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data();
            
            // TODO: Not supported by flutter
           let serviceData = advertiseData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data];
            
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
            
            var deviceDiscoveryMessage = [
                "manufacturerSpecificData": manufacturerData,
//                "serviceData": serviceData.map(),
//                "txPower": Int32(txPowerLevel),
                "address": peripheral.identifier.uuidString,
                "rssi": Int32(rssi)
//                "connectable": connectable
            ] as [String : Any]
            
            if (localName != nil) {
                deviceDiscoveryMessage["deviceName"] = localName
            }
            
            if (serviceUUIDs != nil) {
                deviceDiscoveryMessage["serviceUuids"] = serviceUUIDs
            }
            
            if (overflowServiceUUIDs != nil) {
                deviceDiscoveryMessage["overflowServiceUUIDs"] = overflowServiceUUIDs
            }
            
            if (isConnectable != nil) {
                deviceDiscoveryMessage["connectable"] = isConnectable
            }
            
            if (solicitedServiceUUIDs != nil) {
                deviceDiscoveryMessage["serviceSolicitationUuids"] = solicitedServiceUUIDs
            }
            
//            if (serviceData != nil) {
//                deviceDiscoveryMessage["serviceData"] = serviceData
//            }
            
            if (txPowerLevel != nil) {
                deviceDiscoveryMessage["txPower"] = txPowerLevel
            }
            
            
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
