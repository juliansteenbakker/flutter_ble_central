#include "flutter_ble_central_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <shellapi.h>
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

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

namespace flutter_ble_central {

// static
void FlutterBleCentralPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.steenbakker.flutter_ble_central/method",
          &flutter::StandardMethodCodec::GetInstance());

auto event_scan_result =
    std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), "dev.steenbakker.flutter_ble_central/scan_result",
        &flutter::StandardMethodCodec::GetInstance());

  auto event_state_changed =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.steenbakker.flutter_ble_central/ble_state_changed",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterBleCentralPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<>>(
      [plugin_pointer = plugin.get()](
          const flutter::EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnListen(arguments, std::move(events));
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnCancel(arguments);
      });
  event_scan_result->SetStreamHandler(std::move(handler));

  auto state_handler = std::make_unique<
      flutter::StreamHandlerFunctions<>>(
      [plugin_pointer = plugin.get()](
          const flutter::EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnStateListenInternal(arguments, std::move(events));
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnStateCancelInternal(arguments);
      });
  event_state_changed->SetStreamHandler(std::move(state_handler));

  registrar->AddPlugin(std::move(plugin));
}

FlutterBleCentralPlugin::FlutterBleCentralPlugin() {
  InitializeAsync();
  }

FlutterBleCentralPlugin::~FlutterBleCentralPlugin() {}

winrt::fire_and_forget FlutterBleCentralPlugin::InitializeAsync() {
  try {
    auto bluetoothAdapter = co_await BluetoothAdapter::GetDefaultAsync();
    if (bluetoothAdapter) {
      bluetoothRadio = co_await bluetoothAdapter.GetRadioAsync();
      if (bluetoothRadio) {
        radioStateChangedToken = bluetoothRadio.StateChanged({ this, &FlutterBleCentralPlugin::OnRadioStateChanged });
      }
    }
  }
  catch (...) {
    // Bluetooth adapter not available or initialization failed
    bluetoothRadio = nullptr;
  }
}

void FlutterBleCentralPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));

    } else if (method_call.method_name().compare("isSupported") == 0) {
      // Check if Bluetooth adapter exists
      result->Success(flutter::EncodableValue(bluetoothRadio != nullptr));
    } else if (method_call.method_name().compare("isBluetoothOn") == 0) {
      bool isOn = false;
      try {
        if (bluetoothRadio) {
          isOn = (bluetoothRadio.State() == RadioState::On);
        }
      }
      catch (...) {
        isOn = false;
      }
      result->Success(flutter::EncodableValue(isOn));
    } else if (method_call.method_name().compare("hasPermission") == 0) {
      // Windows doesn't have a permission system like mobile platforms
      // Return "granted" (0) if Bluetooth is available
      result->Success(flutter::EncodableValue(bluetoothRadio != nullptr ? 0 : 1));
    } else if (method_call.method_name().compare("requestPermission") == 0) {
      // Windows doesn't require permission requests
      result->Success(flutter::EncodableValue(bluetoothRadio != nullptr ? 0 : 1));
    } else if (method_call.method_name().compare("enableBluetooth") == 0) {
      EnableBluetoothAsync(std::move(result));
      return;
    } else if (method_call.method_name().compare("openBluetoothSettings") == 0) {
      // Open Windows Bluetooth settings
      ShellExecuteA(nullptr, "open", "ms-settings:bluetooth", nullptr, nullptr, SW_SHOWNORMAL);
      result->Success(nullptr);
    } else if (method_call.method_name().compare("openAppSettings") == 0) {
      // Open Windows app settings
      ShellExecuteA(nullptr, "open", "ms-settings:appsfeatures", nullptr, nullptr, SW_SHOWNORMAL);
      result->Success(nullptr);
    } else if (method_call.method_name().compare("start") == 0) {
      try {
        if (!bluetoothLEWatcher) {
          bluetoothLEWatcher = BluetoothLEAdvertisementWatcher();
          bluetoothLEWatcher.ScanningMode(BluetoothLEScanningMode::Active);
          bluetoothLEWatcherReceivedToken = bluetoothLEWatcher.Received({ this, &FlutterBleCentralPlugin::BluetoothLEWatcher_Received });
          bluetoothLEWatcher.Stopped({ this, &FlutterBleCentralPlugin::BluetoothLEWatcher_Stopped });
        }
        auto status = bluetoothLEWatcher.Status();
        if (status != BluetoothLEAdvertisementWatcherStatus::Started) {
          bluetoothLEWatcher.Start();
        }
        result->Success(nullptr);
      } catch (winrt::hresult_error const& e) {
        bluetoothLEWatcher = nullptr;
        result->Error("start_failed", winrt::to_string(e.message()));
      } catch (...) {
        bluetoothLEWatcher = nullptr;
        result->Error("start_failed", "Failed to start scanning");
      }
    } else if (method_call.method_name().compare("stop") == 0) {
      try {
        if (bluetoothLEWatcher) {
          bluetoothLEWatcher.Stop();
          bluetoothLEWatcher.Received(bluetoothLEWatcherReceivedToken);
        }
        bluetoothLEWatcher = nullptr;
        result->Success(nullptr);
      }
      catch (...) {
        bluetoothLEWatcher = nullptr;
        result->Error("stop_failed", "Failed to stop scanning");
      }
  } else {
    result->NotImplemented();
  }
}

union uint16_t_union {
  uint16_t uint16;
  byte bytes[sizeof(uint16_t)];
};

std::vector<uint8_t> to_bytevc(IBuffer buffer) {
  try {
    if (!buffer) {
      return std::vector<uint8_t>();
    }
    auto reader = DataReader::FromBuffer(buffer);
    auto result = std::vector<uint8_t>(reader.UnconsumedBufferLength());
    reader.ReadBytes(result);
    return result;
  }
  catch (...) {
    return std::vector<uint8_t>();
  }
}

std::vector<uint8_t> parseManufacturerData(BluetoothLEAdvertisement advertisement)  {
  try {
    if (advertisement.ManufacturerData().Size() == 0)
      return std::vector<uint8_t>();
    auto manufacturerData = advertisement.ManufacturerData().GetAt(0);
    // FIXME Compat with REG_DWORD_BIG_ENDIAN
    //uint8_t* prefix = uint16_t_union{ manufacturerData.CompanyId() }.bytes;

    //auto result = std::vector<uint8_t>{ prefix, prefix + sizeof(uint16_t_union) };
    auto data = to_bytevc(manufacturerData.Data());

    //result.insert(result.end(), data.begin(), data.end());
    return data;
  }
  catch (...) {
    return std::vector<uint8_t>();
  }
}

void FlutterBleCentralPlugin::BluetoothLEWatcher_Stopped(
    BluetoothLEAdvertisementWatcher sender,
    BluetoothLEAdvertisementWatcherStoppedEventArgs args) {
    // OutputDebugString((L"Stopped ".c_str());
    // Currently unused, but exception-safe
}

winrt::fire_and_forget FlutterBleCentralPlugin::BluetoothLEWatcher_Received(
    BluetoothLEAdvertisementWatcher sender,
    BluetoothLEAdvertisementReceivedEventArgs args) {
  try {
    // Extract all data on the callback thread first
    auto manufacturer_data = parseManufacturerData(args.Advertisement());
    auto bluetoothAddress = args.BluetoothAddress();
    auto localName = args.Advertisement().LocalName();
    auto name = winrt::to_string(localName);
    if (localName.empty()) {
      std::stringstream sstream;
      sstream << std::hex << bluetoothAddress;
      name = sstream.str();
    }
    auto manufacturerId = args.Advertisement().ManufacturerData().Size() > 0
        ? args.Advertisement().ManufacturerData().GetAt(0).CompanyId()
        : 0;
    auto rssi = args.RawSignalStrengthInDBm();
    auto address = std::to_string(bluetoothAddress);

    // Switch to UI thread before sending to Flutter
    co_await ui_thread_;

    if (scan_result_sink_) {
      scan_result_sink_->Success(flutter::EncodableMap{
        {"deviceName", name},
        {"address", address},
        {"manufacturerSpecificData", manufacturer_data},
        {"rssi", rssi},
        {"manufacturerId", manufacturerId},
      });
    }
  }
  catch (...) {
    // Silently ignore failed advertisement processing
  }
}



std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnListenInternal(
    const flutter::EncodableValue* arguments, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
{
  scan_result_sink_ = std::move(events);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnCancelInternal(
    const flutter::EncodableValue* arguments)
{
    scan_result_sink_ = nullptr;
  return nullptr;
}

// State changed event channel handlers
std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnStateListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
{
  state_changed_sink_ = std::move(events);
  // Send current state to new listener
  PublishState(GetCurrentState());
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnStateCancelInternal(
    const flutter::EncodableValue* arguments)
{
  state_changed_sink_ = nullptr;
  return nullptr;
}

winrt::fire_and_forget FlutterBleCentralPlugin::OnRadioStateChanged(Radio sender, IInspectable args) {
  try {
    auto state = GetCurrentState();
    co_await ui_thread_;
    PublishState(state);
  }
  catch (...) {
    // Ignore state change errors
  }
}

// CentralState enum values matching Dart:
// 0 = unknown, 1 = unsupported, 2 = unauthorized, 3 = poweredOff, 4 = idle
int FlutterBleCentralPlugin::GetCurrentState() {
  if (!bluetoothRadio) {
    return 1; // unsupported
  }
  try {
    switch (bluetoothRadio.State()) {
      case RadioState::On:
        return 4; // idle (ready)
      case RadioState::Off:
        return 3; // poweredOff
      case RadioState::Disabled:
        return 2; // unauthorized (disabled by policy)
      default:
        return 0; // unknown
    }
  }
  catch (...) {
    return 1; // unsupported - radio no longer available
  }
}

void FlutterBleCentralPlugin::PublishState(int state) {
  if (state_changed_sink_) {
    state_changed_sink_->Success(flutter::EncodableValue(state));
  }
}

winrt::fire_and_forget FlutterBleCentralPlugin::EnableBluetoothAsync(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!bluetoothRadio) {
    result->Success(flutter::EncodableValue(false));
    co_return;
  }

  bool success = false;
  try {
    auto accessStatus = co_await bluetoothRadio.SetStateAsync(RadioState::On);
    success = (accessStatus == RadioAccessStatus::Allowed);
  } catch (...) {
    success = false;
  }
  co_await ui_thread_;
  result->Success(flutter::EncodableValue(success));
}

}  // namespace flutter_ble_central
