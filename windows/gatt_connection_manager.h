#ifndef FLUTTER_PLUGIN_GATT_CONNECTION_MANAGER_H_
#define FLUTTER_PLUGIN_GATT_CONNECTION_MANAGER_H_

// This must be included before many other Windows headers.
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>

#include <flutter/standard_method_codec.h>

#include <atomic>
#include <functional>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace flutter_ble_central {

using MethodResult = std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

// Thrown by the uuid parser. Reaching Dart as an error rather than taking the
// process down means parsing has to happen before a coroutine starts, since an
// exception escaping a fire_and_forget calls winrt::terminate.
//
// std::runtime_error keeps only the pointer it is handed, so a message built at
// run time is dangling by the time it is caught. This owns it.
class InvalidArgument : public std::exception {
 public:
  explicit InvalidArgument(std::string message) : message_(std::move(message)) {}
  const char* what() const noexcept override { return message_.c_str(); }

 private:
  std::string message_;
};

// Accepts the 16 bit ("A1B2"), 32 bit ("A1B2C3D4") and 128 bit forms, expanding
// the short ones onto the Bluetooth Base UUID the way Android's UUID does.
winrt::guid ParseUuid(const std::string& value);

// The canonical lowercase form, so a uuid round-trips against the one Dart sent
// and matches what the Android implementation reports.
std::string FormatUuid(const winrt::guid& value);

// Mirrors the Dart `GattConnectionState`. Windows only distinguishes connected
// from disconnected; connecting is reported while a connect is in flight.
enum class ConnectionState {
  Disconnected = 0,
  Connecting = 1,
  Connected = 2,
  Disconnecting = 3,
};

// Mirrors the Dart `BondState`, whose values are Android's BOND_* constants.
enum class BondState {
  None = 10,
  Bonding = 11,
  Bonded = 12,
};

// Serves the GATT client half on Windows: holds a connection per peripheral,
// caches what it serves, and answers each Dart call once the radio has actually
// finished the operation rather than when the request went in.
//
// Every member is touched on the UI thread only. WinRT delivers its completions
// and events on the thread pool, so each coroutine hops back before it reads or
// writes anything here.
class GattConnectionManager {
 public:
  using StateCallback =
      std::function<void(const std::string& address, ConnectionState state)>;
  using ValueCallback = std::function<void(const std::string& address,
                                           const std::string& service_uuid,
                                           const std::string& characteristic_uuid,
                                           const std::vector<uint8_t>& value)>;
  using BondCallback =
      std::function<void(const std::string& address, BondState state)>;

  GattConnectionManager(std::shared_ptr<std::atomic_bool> alive,
                        winrt::apartment_context ui_thread);
  ~GattConnectionManager();

  GattConnectionManager(const GattConnectionManager&) = delete;
  GattConnectionManager& operator=(const GattConnectionManager&) = delete;

  void SetCallbacks(StateCallback on_state, ValueCallback on_value,
                    BondCallback on_bond);

  // Each of these answers `result` exactly once, and only after the radio is
  // done. None of them lets an exception escape.
  winrt::fire_and_forget Connect(uint64_t address, MethodResult result);
  winrt::fire_and_forget Disconnect(uint64_t address, MethodResult result);
  winrt::fire_and_forget DiscoverServices(uint64_t address, MethodResult result);
  winrt::fire_and_forget ReadCharacteristic(uint64_t address,
                                            winrt::guid service_uuid,
                                            winrt::guid characteristic_uuid,
                                            MethodResult result);
  winrt::fire_and_forget WriteCharacteristic(uint64_t address,
                                             winrt::guid service_uuid,
                                             winrt::guid characteristic_uuid,
                                             std::vector<uint8_t> value,
                                             bool without_response,
                                             MethodResult result);
  winrt::fire_and_forget SetCharacteristicNotification(
      uint64_t address, winrt::guid service_uuid,
      winrt::guid characteristic_uuid, bool enable, MethodResult result);
  winrt::fire_and_forget ReadDescriptor(uint64_t address,
                                        winrt::guid service_uuid,
                                        winrt::guid characteristic_uuid,
                                        winrt::guid descriptor_uuid,
                                        MethodResult result);
  winrt::fire_and_forget WriteDescriptor(uint64_t address,
                                         winrt::guid service_uuid,
                                         winrt::guid characteristic_uuid,
                                         winrt::guid descriptor_uuid,
                                         std::vector<uint8_t> value,
                                         MethodResult result);
  winrt::fire_and_forget CreateBond(uint64_t address, MethodResult result);
  winrt::fire_and_forget RemoveBond(uint64_t address, MethodResult result);

  // Answered from what is already known, so these stay synchronous.
  ConnectionState GetConnectionState(uint64_t address) const;
  int GetMtu(uint64_t address) const;

  // Drops every connection. Called while the plugin is being torn down, so it
  // revokes before it releases.
  void CloseAll();

 private:
  struct Connection {
    winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device{nullptr};
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession
        session{nullptr};
    winrt::event_token connection_status_token{};

    // Filled in by discoverServices, so a read or a write finds its
    // characteristic without going back to the peripheral for it.
    std::vector<winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
                    GattDeviceService>
        services;
    std::map<std::string, winrt::Windows::Devices::Bluetooth::
                              GenericAttributeProfile::GattCharacteristic>
        characteristics;
    std::map<std::string, winrt::event_token> value_tokens;

    // The last state published, so only changes are sent.
    ConnectionState state = ConnectionState::Disconnected;

    // Bumped by every connect and disconnect, so an operation still in flight
    // cannot report against the connection that replaced it.
    uint32_t token = 0;
  };

  // The connection for this address, or nullptr when there is none. UI thread.
  Connection* Find(const std::string& key);
  const Connection* Find(const std::string& key) const;

  // Looks up a characteristic that discoverServices already found. Returns
  // false with `error` set when it has not been discovered.
  bool FindCharacteristic(
      const std::string& key, const winrt::guid& service_uuid,
      const winrt::guid& characteristic_uuid,
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristic& characteristic,
      std::string& error) const;

  // Tears one connection down: revokes every handler, then releases. UI thread.
  void Close(const std::string& key);

  void PublishState(const std::string& key, ConnectionState state);

  // Follows the link, which is the only thing that reports a peripheral going
  // away on its own.
  winrt::fire_and_forget OnConnectionStatusChanged(
      winrt::Windows::Devices::Bluetooth::BluetoothLEDevice sender,
      winrt::Windows::Foundation::IInspectable args);

  // Hands a notification to Dart. A ValueChanged arrives on the thread pool, so
  // this hops back before it touches anything.
  winrt::fire_and_forget PublishValue(std::string address,
                                      std::string service_uuid,
                                      std::string characteristic_uuid,
                                      std::vector<uint8_t> value);

  std::shared_ptr<std::atomic_bool> alive_;
  winrt::apartment_context ui_thread_;

  StateCallback on_state_;
  ValueCallback on_value_;
  BondCallback on_bond_;

  std::map<std::string, Connection> connections_;

  // Handed to each connection as it is made, so that an operation still in
  // flight can tell a reconnect from the connection it started against.
  uint32_t next_token_ = 0;
};

}  // namespace flutter_ble_central

#endif  // FLUTTER_PLUGIN_GATT_CONNECTION_MANAGER_H_
