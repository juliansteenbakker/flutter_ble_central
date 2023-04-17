//
//  CentralState.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 12/04/2023.
//

import Foundation

enum CentralState: Int {
    case Granted = 0 /// The user denied access to the requested feature, permission needs to be asked first.
    case Denied = 1  /// Permission to the requested feature is permanently denied,

    /// the permission dialog will not be shown when requesting this permission.
    /// The user may still change the permission status in the settings.
    case PermanentlyDenied = 2  /// The status is unknown


    /// The user cannot change this app's status, possibly due to active restrictions such as parental controls being in place.
    ///
    /// Only supported on iOS.
    case Restricted = 3  /// User has authorized this application for limited access.

    /// Only supported on iOS (iOS14+).
    case Limited = 4  /// Bluetooth is turned off
    case TurnedOff = 5
    case Unsupported = 6
    case Unknown = 7
    case Ready = 8
    
}
