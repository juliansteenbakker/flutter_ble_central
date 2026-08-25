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

#include <atomic>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
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
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> state_changed_sink_;

  Radio bluetoothRadio{ nullptr };
  winrt::event_token radioStateChangedToken;

  // UI thread context for dispatching callbacks to Flutter
  winrt::apartment_context ui_thread_;

  BluetoothLEAdvertisementWatcher bluetoothLEWatcher{ nullptr };
  winrt::event_token bluetoothLEWatcherReceivedToken;
  winrt::fire_and_forget BluetoothLEWatcher_Received(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args);
  void BluetoothLEWatcher_Stopped(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementWatcherStoppedEventArgs args);

  // State changed event channel handlers
  std::unique_ptr<flutter::StreamHandlerError<>> OnStateListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<>>&& events);
  std::unique_ptr<flutter::StreamHandlerError<>> OnStateCancelInternal(
      const flutter::EncodableValue* arguments);

  winrt::fire_and_forget OnRadioStateChanged(Radio sender, IInspectable args);
  void PublishState(int state);
  int GetCurrentState();

  winrt::fire_and_forget EnableBluetoothAsync(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // GATT client
  //
  // Windows has no explicit connect: a link comes up when the services of a
  // device are asked for, and is held for as long as the BluetoothLEDevice is
  // alive. So connect() resolves the device and discovers, and disconnect()
  // drops the reference.

  using Result = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

  // What a connected device holds on to. The session is only kept for the MTU.
  struct Connection {
    BluetoothLEDevice device{ nullptr };
    GattSession session{ nullptr };
    winrt::event_token connection_changed_token;
    std::map<std::string, winrt::event_token> value_changed_tokens;
  };

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> connection_state_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> characteristic_value_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> bond_state_sink_;

  std::map<uint64_t, Connection> connections_;

  winrt::fire_and_forget ConnectAsync(uint64_t address, Result result);
  void Disconnect(uint64_t address);
  winrt::fire_and_forget DiscoverServicesAsync(uint64_t address, Result result);
  winrt::fire_and_forget ReadCharacteristicAsync(
      uint64_t address, std::string service, std::string characteristic, Result result);
  winrt::fire_and_forget WriteCharacteristicAsync(
      uint64_t address, std::string service, std::string characteristic,
      std::vector<uint8_t> value, bool without_response, Result result);
  winrt::fire_and_forget SetNotifyAsync(
      uint64_t address, std::string service, std::string characteristic,
      bool enable, Result result);
  winrt::fire_and_forget ReadDescriptorAsync(
      uint64_t address, std::string service, std::string characteristic,
      std::string descriptor, Result result);
  winrt::fire_and_forget WriteDescriptorAsync(
      uint64_t address, std::string service, std::string characteristic,
      std::string descriptor, std::vector<uint8_t> value, Result result);
  winrt::fire_and_forget PairAsync(uint64_t address, bool pair, Result result);

  // Reports the link state on the connection_state channel.
  void PublishConnectionState(uint64_t address, int state);

  // The characteristic named, or nullptr with the error already reported.
  IAsyncOperation<GattCharacteristic> FindCharacteristic(
      uint64_t address, std::string service, std::string characteristic);

  // Cleared when the plugin is destroyed, so a coroutine resuming afterwards
  // does not touch it.
  std::shared_ptr<std::atomic_bool> alive_ = std::make_shared<std::atomic_bool>(true);
};

}  // namespace flutter_ble_central

#endif  // FLUTTER_PLUGIN_FLUTTER_BLE_CENTRAL_PLUGIN_H_
