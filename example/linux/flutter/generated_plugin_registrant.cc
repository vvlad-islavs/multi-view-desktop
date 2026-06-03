//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <multiview_desktop/multiview_desktop_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) multiview_desktop_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MultiviewDesktopPlugin");
  multiview_desktop_plugin_register_with_registrar(multiview_desktop_registrar);
}
