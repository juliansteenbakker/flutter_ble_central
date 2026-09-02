# Migration guide

## 0.3.x to 1.0.0

### Renamed, old names still work

`BluetoothCentralState` is now `CentralBluetoothState`, and
`onPeripheralStateChanged` is now `onCentralStateChanged`. Both old names stay
available as deprecated aliases in this release and are removed in the next
breaking one, so existing code keeps compiling and the analyzer points at the
replacement.

The rename exists so this package and `flutter_ble_peripheral` no longer declare
colliding type names when both are used in one app.

### Removed

`isAdvertising` is gone. It was declared in Dart but no platform ever
implemented a handler for it, so every call threw `MissingPluginException` on
every platform. There is no replacement: advertising is a peripheral-mode
operation and belongs to `flutter_ble_peripheral`.

### Changed behaviour

On Android, a disabled Bluetooth adapter now reports
`CentralBluetoothState.turnedOff` instead of `denied`. This matches what the
Darwin side already returned for `poweredOff`.

This one does not break the build, so it needs a manual check. If you branch on
`denied` to trigger a permission prompt, that branch no longer fires when the
adapter is merely switched off, and you should handle `turnedOff` by asking the
user to enable Bluetooth instead.
