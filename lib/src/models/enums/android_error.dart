enum AndroidError {
  scanFailedAlreadyStarted,
  scanFailedApplicationRegistrationFailed,
  scanFailedInternalError,
  scanFailedFeatureUnsupported,
  scanFailedOutOfHardwareResources,
  scanFailedScanningTooFrequently
}

extension AndroidErrorExtension on AndroidError {
  int get code {
    switch (this) {
      case AndroidError.scanFailedAlreadyStarted:
        return 1;
      case AndroidError.scanFailedApplicationRegistrationFailed:
        return 2;
      case AndroidError.scanFailedInternalError:
        return 3;
      case AndroidError.scanFailedFeatureUnsupported:
        return 4;
      case AndroidError.scanFailedOutOfHardwareResources:
        return 5;
      case AndroidError.scanFailedScanningTooFrequently:
        return 6;
    }
  }
}
