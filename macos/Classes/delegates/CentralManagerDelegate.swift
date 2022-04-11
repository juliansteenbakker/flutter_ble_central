//
//  CentralManagerDelegate.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import CoreBluetooth
final class CentralManagerDelegate: NSObject, CBCentralManagerDelegate {


    typealias StateChangeHandler = (CBManagerState) -> Void
    typealias DiscoveryHandler = (CBPeripheral, AdvertisementData, RSSI) -> Void

    private let onStateChange: StateChangeHandler
    private let onDiscovery: DiscoveryHandler

    init(
        onStateChange: @escaping StateChangeHandler,
        onDiscovery: @escaping DiscoveryHandler
    ) {
        self.onStateChange = onStateChange
        self.onDiscovery = onDiscovery
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange(central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        onDiscovery(peripheral, advertisementData, rssi.intValue)
    }

}
