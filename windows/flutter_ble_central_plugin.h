#ifndef FLUTTER_PLUGIN_FLUTTER_BLE_CENTRAL_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_BLE_CENTRAL_PLUGIN_H_

// This must be included before many other Windows headers.
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>

#include <flutter/method_channel.h>
#include <flutter/basic_message_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>

#include "gatt_connection_manager.h"

#include <atomic>
#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace flutter_ble_central {

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Foundation::Collections;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::Devices::Radios;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace winrt::Windows::Devices::Enumeration;

using flutter::EncodableMap;
using flutter::EncodableValue;


class FlutterBleCentralPlugin : public flutter::Plugin, public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterBleCentralPlugin();

  virtual ~FlutterBleCentralPlugin();

  // Disallow copy and assign.
  FlutterBleCentralPlugin(const FlutterBleCentralPlugin&) = delete;
  FlutterBleCentralPlugin& operator=(const FlutterBleCentralPlugin&) = delete;

 private:
    winrt::fire_and_forget InitializeAsync();

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    std::unique_ptr<flutter::StreamHandlerError<>> OnListenInternal(
        const flutter::EncodableValue* arguments,
        std::unique_ptr<flutter::EventSink<>>&& events) override;
    std::unique_ptr<flutter::StreamHandlerError<>> OnCancelInternal(
        const flutter::EncodableValue* arguments) override;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> scan_result_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> state_changed_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> connection_state_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> characteristic_value_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> bond_state_sink_;

  // Serves the GATT client half. Created once the plugin is up, so that it can
  // be handed the apartment this plugin was registered on.
  std::unique_ptr<GattConnectionManager> gatt_;

  // Whether a method belongs to the GATT client half.
  static bool IsConnectionMethod(const std::string& method);

  // Reads what a connection method needs out of the arguments and hands it to
  // the manager, or answers with an error when Dart sent something unusable.
  void HandleConnectionMethod(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Reports a method Windows has no way to serve, rather than letting it fall
  // through to a missing-plugin failure.
  void ReportUnsupported(
      const std::string& method,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  Radio bluetoothRadio{ nullptr };
  winrt::event_token radioStateChangedToken;

  // UI thread context for dispatching callbacks to Flutter
  winrt::apartment_context ui_thread_;

  BluetoothLEAdvertisementWatcher bluetoothLEWatcher{ nullptr };
  winrt::event_token bluetoothLEWatcherReceivedToken;
  winrt::event_token bluetoothLEWatcherStoppedToken;
  winrt::fire_and_forget BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args);
  void BluetoothLEWatcher_Stopped(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementWatcherStoppedEventArgs args);

  // State changed event channel handlers
  std::unique_ptr<flutter::StreamHandlerError<>> OnStateListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<>>&& events);
  std::unique_ptr<flutter::StreamHandlerError<>> OnStateCancelInternal(
      const flutter::EncodableValue* arguments);

  winrt::fire_and_forget OnRadioStateChanged(Radio sender, IInspectable args);

  // Publishes a state unless it is the one already reported, and remembers it
  // for a listener attaching later. Must be called on the UI thread.
  void PublishState(int state);

  // Hands the current state to a listener that just attached.
  void SendCurrentState();

  int GetCurrentState();

  // The last state published. Until InitializeAsync has looked the adapter up
  // there is nothing to report on, so it starts out unknown rather than
  // claiming the adapter is unsupported.
  int central_state_ = 0;

  // Cleared when the plugin is destroyed, so that a coroutine resuming after
  // the fact does not touch it.
  std::shared_ptr<std::atomic_bool> alive_ = std::make_shared<std::atomic_bool>(true);

  winrt::fire_and_forget EnableBluetoothAsync(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_ble_central

#endif  // FLUTTER_PLUGIN_FLUTTER_BLE_CENTRAL_PLUGIN_H_
