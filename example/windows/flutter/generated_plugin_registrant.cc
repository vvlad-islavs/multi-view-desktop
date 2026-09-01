//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <multiview_desktop/multi_view_desktop_plugin.h>
#include <tray_manager/tray_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  MultiViewDesktopPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MultiViewDesktopPlugin"));
  TrayManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("TrayManagerPlugin"));
}
