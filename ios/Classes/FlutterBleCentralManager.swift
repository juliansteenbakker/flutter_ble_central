//
//  FlutterBleCentralManager.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import CoreBluetooth

typealias RSSI = Int

typealias PeripheralID = UUID
typealias ServiceID = CBUUID
typealias CharacteristicID = CBUUID

typealias ServiceData = [ServiceID: Data]
typealias AdvertisementData = [String: Any]


final class FlutterBleCentralManager {

    
//    let scanResultHandler: ScanResultHandler
//    let stateChangedHandler: StateChangedHandler
//
//    typealias StateChangeHandler = (CBManagerState) -> Void
//    typealias DiscoveryHandler = (CBPeripheral, AdvertisementData, RSSI) -> Void
//    typealias StateChangeHandler = (Central, CBManagerState) -> Void
//    typealias DiscoveryHandler = (CBPeripheral, AdvertisementData, RSSI) -> Void
//    typealias ServicesWithCharacteristicsDiscoveryHandler = (Central, CBPeripheral, [Error]) -> Void

//    private var centralManagerDelegate: CentralManagerDelegate!
//    private var centralManagerLegacyDelegate: LegacyCentralManagerDelegate!
    private let centralManager: CBCentralManager
    private let centralManagerDelegate: CentralManagerDelegate

    private(set) var isScanning = false
    private(set) var activePeripherals = [PeripheralID: CBPeripheral]()
    
    init(
        scanResultHandler: ScanResultHandler,
        stateChangedHandler: StateChangedHandler
//        onStateChange: @escaping StateChangeHandler,
//        onDiscovery: @escaping DiscoveryHandler
    ) {
        
        self.centralManagerDelegate = CentralManagerDelegate(
            onStateChange: { (state) in
                stateChangedHandler.publishPeripheralState(state: state)
            },
            onDiscovery: {(CBPeripheral, AdvertisementData, RSSI) in
                scanResultHandler.publishScanResult(advertiseData: AdvertisementData, rssi: RSSI)
            }
        )
        
        self.centralManager = CBCentralManager(
            delegate:self.centralManagerDelegate,
            queue: nil
        )
        
//        if #available(iOS 10.0, *) {
//
//
//            self.centralManager = CBCentralManager(
//                delegate:self.centralManagerDelegate,
//                queue: nil
//            )
//
//        } else {
//            self.centralManager = CBCentralManager(
//                delegate: LegacyCentralManagerDelegate(
//                    onStateChange: { state in
//                        stateChangedHandler.publishLegacyPeripheralState(state: state)
//                    },
//                    onDiscovery: {CBPeripheral, AdvertisementData, RSSI in
//                        scanResultHandler.publishScanResult(advertiseData: AdvertisementData, rssi: 3)
//                    }
//                ),
//                queue: nil
//            )
//        }
        
    }

    func startScan(with services: [ServiceID]?) {
        isScanning = true
        if (centralManager.state != CBManagerState.poweredOn) {
            print("CBCentralManager must be powered to scan peripherals. %d", self.centralManager.state);
        }
        centralManager.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    private enum Failure: Error, CustomStringConvertible {

        case notPoweredOn(actualState: CBCentralManagerState)
        case peripheralIsUnknown(PeripheralID)
        case peripheralIsNotConnected(PeripheralID)
        case serviceNotFound(ServiceID, PeripheralID)

        var description: String {
            switch self {
            case .notPoweredOn(let actualState):
                return "Bluetooth is not powered on (the current state code is \(actualState.rawValue))"
            case .peripheralIsUnknown(let peripheralID):
                return "A peripheral \(peripheralID.uuidString) is unknown (make sure it has been discovered)"
            case .peripheralIsNotConnected(let peripheralID):
                return "The peripheral \(peripheralID.uuidString) is not connected"
            case .serviceNotFound(let serviceID, let peripheralID):
                return "A service \(serviceID) is not found in the peripheral \(peripheralID) (make sure it has been discovered)"
            }
        }
    }
}
