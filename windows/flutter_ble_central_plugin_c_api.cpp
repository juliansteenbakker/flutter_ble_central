#include "include/flutter_ble_central/flutter_ble_central_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_ble_central_plugin.h"

void FlutterBleCentralPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_ble_central::FlutterBleCentralPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
