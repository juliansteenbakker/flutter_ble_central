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

#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>

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

  Radio bluetoothRadio{ nullptr };

  BluetoothLEAdvertisementWatcher bluetoothLEWatcher{ nullptr };
  winrt::event_token bluetoothLEWatcherReceivedToken;
  void BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args);



};

}  // namespace flutter_ble_central

#endif  // FLUTTER_PLUGIN_FLUTTER_BLE_CENTRAL_PLUGIN_H_
