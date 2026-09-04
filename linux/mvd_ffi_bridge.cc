// MVD FFI bridge: C ABI called from Dart `FfiBridge`.
// Dart UI isolate == GTK main thread; no dispatch hop.

#include "mvd_linux_internal.h"
#include "mvd_linux_taskbar_menu.h"
#include "mvd_linux_window.h"

#include <gtk/gtk.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>

#include <multiview_desktop/multiview_desktop_plugin.h>

namespace {

constexpr int kStrCap = 8192;

double g_rect_buf[4] = {0, 0, 0, 0};
char g_str_buf[kStrCap] = {};
char g_str_buf2[kStrCap] = {};
int32_t g_i32_buf[8] = {};
FlValue* g_pending_menu = nullptr;

void ClearRectBuf() {
  g_rect_buf[0] = 0;
  g_rect_buf[1] = 0;
  g_rect_buf[2] = 0;
  g_rect_buf[3] = 0;
}

double OverlapArea(double ax, double ay, double aw, double ah, double bx,
                   double by, double bw, double bh) {
  const double left = std::max(ax, bx);
  const double top = std::max(ay, by);
  const double right = std::min(ax + aw, bx + bw);
  const double bottom = std::min(ay + ah, by + bh);
  const double w = right - left;
  const double h = bottom - top;
  if (w <= 0 || h <= 0) {
    return 0;
  }
  return w * h;
}

std::shared_ptr<MvdLinuxWindow> Win(int64_t id) { return MvdLinuxWindow::Find(id); }

MvdEventCallback g_event_cb = nullptr;
bool g_event_cb_installed = false;
uint64_t g_event_cb_generation = 0;

}  // namespace

extern "C" {

FLUTTER_PLUGIN_EXPORT void mvd_set_event_callback(MvdEventCallback cb) {
  g_event_cb = cb;
  ++g_event_cb_generation;
  if (cb) {
    g_event_cb_installed = true;
  }
}

FLUTTER_PLUGIN_EXPORT int64_t mvd_event_callback_generation() {
  return static_cast<int64_t>(g_event_cb_generation);
}

FLUTTER_PLUGIN_EXPORT void mvd_detach_isolate_callbacks(void* token) {
  const auto gen = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(token));
  if (gen != g_event_cb_generation) {
    return;
  }
  g_event_cb = nullptr;
  mvd_linux_clear_screen_event_callback();
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_emit_event(const char* event_name,
                                             int64_t view_id, int64_t arg) {
  if (g_event_cb_installed) {
    if (g_event_cb && event_name) {
      g_event_cb(event_name, view_id, arg);
    }
    return 1;
  }
  if (!g_event_cb || !event_name) {
    return 0;
  }
  g_event_cb(event_name, view_id, arg);
  return 1;
}

FLUTTER_PLUGIN_EXPORT double* mvd_rect_buf_ptr() { return g_rect_buf; }
FLUTTER_PLUGIN_EXPORT char* mvd_str_buf_ptr() { return g_str_buf; }
FLUTTER_PLUGIN_EXPORT char* mvd_str_buf2_ptr() { return g_str_buf2; }
FLUTTER_PLUGIN_EXPORT int32_t* mvd_i32_buf_ptr() { return g_i32_buf; }

FLUTTER_PLUGIN_EXPORT int64_t mvd_create_window(int64_t token, double w, double h,
                                             int32_t buttons, int32_t has_pos,
                                             double x, double y,
                                             int64_t) {
  return mvd_linux_queue_create_window(token, w, h, g_str_buf, g_str_buf2, buttons,
                                has_pos, x, y);
}

FLUTTER_PLUGIN_EXPORT int64_t mvd_create_modal_dialog(
    int64_t token, int64_t parent_id, double w, double h, int32_t modal,
    int32_t buttons, int32_t has_pos, double x, double y) {
  return mvd_linux_queue_create_dialog(token, parent_id, static_cast<int>(w),
                                static_cast<int>(h), modal, g_str_buf,
                                g_str_buf2, buttons, has_pos,
                                static_cast<int>(x), static_cast<int>(y));
}

FLUTTER_PLUGIN_EXPORT void mvd_complete_modal_dialog(int64_t view_id) {
  mvd_linux_complete_modal_dialog(view_id);
}

FLUTTER_PLUGIN_EXPORT int64_t mvd_create_popup(int64_t token, int64_t parent_id,
                                            double w, double h) {
  return mvd_linux_queue_create_popup(token, parent_id, static_cast<int>(w),
                               static_cast<int>(h));
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_check_exist(int64_t view_id) {
  return Win(view_id) ? 1 : 0;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_anchor_view_id(int64_t view_id) {
  mvd_linux_set_anchor_view_id(view_id);
}

FLUTTER_PLUGIN_EXPORT void mvd_set_terminate_after_last(int32_t terminate) {
  mvd_linux_set_terminate_after_last(terminate);
}

FLUTTER_PLUGIN_EXPORT void mvd_reply_terminate(int32_t) {}
FLUTTER_PLUGIN_EXPORT void mvd_set_has_taskbar_callback(int32_t) {}

FLUTTER_PLUGIN_EXPORT int32_t mvd_is_hide_app_from_taskbar() {
  std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
  if (MvdLinuxWindow::windows.empty()) {
    return 1;
  }
  for (const auto& p : MvdLinuxWindow::windows) {
    if (!p.second->IsSkipTaskbar()) {
      return 0;
    }
  }
  return 1;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_progress_bar(double) {}

FLUTTER_PLUGIN_EXPORT void mvd_taskbar_menu_clear() {
  if (g_pending_menu) {
    fl_value_unref(g_pending_menu);
  }
  g_pending_menu = fl_value_new_list();
}

FLUTTER_PLUGIN_EXPORT void mvd_taskbar_menu_add(int32_t id) {
  if (!g_pending_menu) {
    g_pending_menu = fl_value_new_list();
  }
  FlValue* item = fl_value_new_map();
  fl_value_set_string_take(item, "id", fl_value_new_int(id));
  fl_value_set_string_take(item, "title", fl_value_new_string(g_str_buf));
  if (g_str_buf2[0] != 0) {
    fl_value_set_string_take(item, "icon", fl_value_new_string(g_str_buf2));
  }
  fl_value_append_take(g_pending_menu, item);
}

FLUTTER_PLUGIN_EXPORT void mvd_taskbar_menu_commit() {
  mvd_linux_set_taskbar_menu(g_pending_menu);
  if (g_pending_menu) {
    fl_value_unref(g_pending_menu);
    g_pending_menu = nullptr;
  }
}

FLUTTER_PLUGIN_EXPORT void mvd_get_frame(int64_t view_id) {
  auto wm = Win(view_id);
  if (!wm || !wm->window) {
    ClearRectBuf();
    return;
  }
  gint x = 0, y = 0, width = 0, height = 0;
  gtk_window_get_position(wm->window, &x, &y);
  gtk_window_get_size(wm->window, &width, &height);
  g_rect_buf[0] = static_cast<double>(x);
  g_rect_buf[1] = static_cast<double>(y);
  g_rect_buf[2] = static_cast<double>(width);
  g_rect_buf[3] = static_cast<double>(height);
}

FLUTTER_PLUGIN_EXPORT void mvd_set_frame(int64_t view_id, double x, double y,
                                         double w, double h) {
  auto wm = Win(view_id);
  if (!wm) {
    return;
  }
  wm->SetPosition(x, y);
  gint cur_w = 0, cur_h = 0;
  if (wm->window) {
    gtk_window_get_size(wm->window, &cur_w, &cur_h);
  }
  if (std::abs(cur_w - w) > 0.5 || std::abs(cur_h - h) > 0.5) {
    wm->SetSize(w, h);
  }
}

FLUTTER_PLUGIN_EXPORT void mvd_get_display_rect(double x, double y, double w,
                                                double h) {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) {
    g_rect_buf[0] = 0;
    g_rect_buf[1] = 0;
    g_rect_buf[2] = 2560;
    g_rect_buf[3] = 1440;
    return;
  }
  const int n = gdk_display_get_n_monitors(display);
  double best_area = -1, best_x = 0, best_y = 0, best_w = 2560, best_h = 1440;
  bool found = false;
  for (int i = 0; i < n; i++) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (!monitor) continue;
    GdkRectangle work{};
    gdk_monitor_get_workarea(monitor, &work);
    const double area = OverlapArea(x, y, w, h, work.x, work.y, work.width,
                                    work.height);
    if (!found || area >= best_area) {
      found = true;
      best_area = area;
      best_x = work.x;
      best_y = work.y;
      best_w = work.width;
      best_h = work.height;
    }
  }
  g_rect_buf[0] = best_x;
  g_rect_buf[1] = best_y;
  g_rect_buf[2] = best_w;
  g_rect_buf[3] = best_h;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_size(int64_t id, double w, double h) {
  if (auto wm = Win(id)) wm->SetSize(w, h);
}
FLUTTER_PLUGIN_EXPORT void mvd_set_position(int64_t id, double x, double y) {
  if (auto wm = Win(id)) wm->SetPosition(x, y);
}
FLUTTER_PLUGIN_EXPORT void mvd_set_min_size(int64_t id, double w, double h) {
  if (auto wm = Win(id)) wm->SetMinimumSize(static_cast<float>(w), static_cast<float>(h));
}
FLUTTER_PLUGIN_EXPORT void mvd_get_min_size(int64_t id) {
  auto wm = Win(id);
  if (!wm) {
    ClearRectBuf();
    return;
  }
  float w = 0, h = 0;
  wm->GetMinimumSize(&w, &h);
  g_rect_buf[0] = static_cast<double>(w);
  g_rect_buf[1] = static_cast<double>(h);
  g_rect_buf[2] = 0;
  g_rect_buf[3] = 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_max_size(int64_t id, double w, double h) {
  if (auto wm = Win(id)) wm->SetMaximumSize(static_cast<float>(w), static_cast<float>(h));
}
FLUTTER_PLUGIN_EXPORT void mvd_get_max_size(int64_t id) {
  auto wm = Win(id);
  if (!wm) {
    ClearRectBuf();
    return;
  }
  float w = 0, h = 0;
  wm->GetMaximumSize(&w, &h);
  g_rect_buf[0] = static_cast<double>(w);
  g_rect_buf[1] = static_cast<double>(h);
  g_rect_buf[2] = 0;
  g_rect_buf[3] = 0;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_background_color(int64_t id, int32_t a,
                                                    int32_t r, int32_t g,
                                                    int32_t b) {
  if (auto wm = Win(id)) wm->SetBackgroundColor(r, g, b, a);
}

FLUTTER_PLUGIN_EXPORT void mvd_set_title(int64_t id) {
  if (auto wm = Win(id)) wm->SetTitle(g_str_buf);
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_title(int64_t id) {
  auto wm = Win(id);
  if (!wm) return 0;
  const gchar* title = wm->GetTitle();
  std::strncpy(g_str_buf, title ? title : "", kStrCap - 1);
  g_str_buf[kStrCap - 1] = 0;
  return 1;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_title_bar_style(int64_t id, int32_t close_v,
                                                   int32_t, int32_t) {
  if (auto wm = Win(id)) wm->SetTitleBarStyle(g_str_buf, close_v != 0);
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_title_bar_style(int64_t id) {
  auto wm = Win(id);
  if (!wm) return 0;
  FlValue* map = wm->GetTitleBarStyle();
  if (!map) return 0;
  FlValue* style = fl_value_lookup_string(map, "style");
  const char* name =
      (style && fl_value_get_type(style) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(style)
          : "normal";
  std::strncpy(g_str_buf, name, kStrCap - 1);
  g_str_buf[kStrCap - 1] = 0;
  FlValue* vis = fl_value_lookup_string(map, "windowButtonVisibility");
  const int32_t v =
      (vis && fl_value_get_type(vis) == FL_VALUE_TYPE_BOOL &&
       fl_value_get_bool(vis))
          ? 1
          : 0;
  g_i32_buf[0] = v;
  g_i32_buf[1] = v;
  g_i32_buf[2] = v;
  fl_value_unref(map);
  return 1;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_as_frameless(int64_t id) {
  if (auto wm = Win(id)) wm->SetAsFrameless();
}
FLUTTER_PLUGIN_EXPORT void mvd_set_always_on_top(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetAlwaysOnTop(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_always_on_top(int64_t id) {
  auto wm = Win(id);
  return wm && wm->IsAlwaysOnTop() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_full_screen(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetFullScreen(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_full_screen(int64_t id) {
  auto wm = Win(id);
  return wm && wm->IsFullScreen() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_hide_app_from_taskbar(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetSkipTaskbar(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_hide_app_tab_from_taskbar(int64_t id) {
  auto wm = Win(id);
  return wm && wm->IsSkipTaskbar() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_close_window(int64_t id) {
  if (auto wm = Win(id)) wm->Close();
}
FLUTTER_PLUGIN_EXPORT void mvd_destroy_window(int64_t id) {
  if (auto wm = Win(id)) wm->Destroy();
}
FLUTTER_PLUGIN_EXPORT void mvd_focus(int64_t id) {
  if (auto wm = Win(id)) wm->Focus();
}
FLUTTER_PLUGIN_EXPORT void mvd_blur(int64_t id) {
  GtkWindow* other = nullptr;
  {
    std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
    auto it = MvdLinuxWindow::windows.find(id);
    if (it == MvdLinuxWindow::windows.end() || !it->second ||
        !it->second->window) {
      return;
    }
    for (const auto& p : MvdLinuxWindow::windows) {
      if (p.first != id && p.second->window && p.second->IsVisible()) {
        other = p.second->window;
        break;
      }
    }
  }
  if (other) {
    gtk_window_present(other);
  }
}
FLUTTER_PLUGIN_EXPORT void mvd_set_pre_confirm(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->is_pre_confirm = v != 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_confirm(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->is_confirm_close = v != 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_prevent_close(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->is_prevent_close = v != 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_prevent_close(int64_t id) {
  auto wm = Win(id);
  return wm && wm->is_prevent_close ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_brightness(int64_t id) {
  if (auto wm = Win(id)) wm->SetBrightness(g_str_buf);
}
FLUTTER_PLUGIN_EXPORT void mvd_set_opacity(int64_t id, double o) {
  if (auto wm = Win(id)) wm->SetOpacity(o);
}
FLUTTER_PLUGIN_EXPORT double mvd_get_opacity(int64_t id) {
  auto wm = Win(id);
  return wm ? wm->GetOpacity() : 1.0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_has_shadow(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->HasShadow() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_has_shadow(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetHasShadow(v != 0);
}
FLUTTER_PLUGIN_EXPORT void mvd_set_aspect_ratio(int64_t id, double r) {
  if (auto wm = Win(id)) wm->SetAspectRatio(static_cast<float>(r));
}
FLUTTER_PLUGIN_EXPORT void mvd_show(int64_t id) {
  if (auto wm = Win(id)) wm->Show();
}
FLUTTER_PLUGIN_EXPORT void mvd_hide(int64_t id) {
  if (auto wm = Win(id)) wm->Hide();
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_visible(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->IsVisible() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_focused(int64_t id) {
  auto wm = Win(id);
  return wm && wm->IsFocused() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_on_active_space(int64_t) { return 1; }
FLUTTER_PLUGIN_EXPORT void mvd_maximize(int64_t id, int32_t) {
  if (auto wm = Win(id)) wm->Maximize();
}
FLUTTER_PLUGIN_EXPORT void mvd_unmaximize(int64_t id) {
  if (auto wm = Win(id)) wm->Unmaximize();
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_maximized(int64_t id) {
  auto wm = Win(id);
  return wm && wm->IsMaximized() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_minimize(int64_t id) {
  if (auto wm = Win(id)) wm->Minimize();
}
FLUTTER_PLUGIN_EXPORT void mvd_restore(int64_t id) {
  if (auto wm = Win(id)) wm->Restore();
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_minimized(int64_t id) {
  auto wm = Win(id);
  return wm && wm->IsMinimized() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_resizable(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->IsResizable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_resizable(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetResizable(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_movable(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->IsMovable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_movable(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetMovable(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_minimizable(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->IsMinimizable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_minimizable(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetMinimizable(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_maximizable(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->IsMaximizable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_maximizable(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetMaximizable(v != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_closable(int64_t id) {
  auto wm = Win(id);
  return !wm || wm->IsClosable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_closable(int64_t id, int32_t v) {
  if (auto wm = Win(id)) wm->SetClosable(v != 0);
}
FLUTTER_PLUGIN_EXPORT void mvd_start_dragging(int64_t id) {
  if (auto wm = Win(id)) wm->StartDragging();
}
FLUTTER_PLUGIN_EXPORT void mvd_start_resizing(int64_t id, int32_t, int32_t,
                                              int32_t, int32_t) {
  if (auto wm = Win(id)) wm->StartResizing(g_str_buf);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_hide_from_collection(int64_t) { return 0; }
FLUTTER_PLUGIN_EXPORT void mvd_hide_from_collection(int64_t, int32_t) {}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_visible_on_all_workspaces(int64_t) {
  return 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_visible_on_all_workspaces(int64_t, int32_t,
                                                              int32_t) {}
FLUTTER_PLUGIN_EXPORT void mvd_set_badge_label(int64_t) {}
FLUTTER_PLUGIN_EXPORT void mvd_set_ignore_mouse_events(int64_t id, int32_t ignore,
                                                       int32_t forward) {
  if (auto wm = Win(id)) wm->SetIgnoreMouseEvents(ignore != 0, forward != 0);
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_ignore_mouse_events(int64_t id) {
  auto wm = Win(id);
  g_i32_buf[0] = 0;
  if (!wm) return 0;
  auto [ignore, forward] = wm->IsIgnoreMouseEvents();
  g_i32_buf[0] = forward ? 1 : 0;
  return ignore ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_pop_up_window_menu(int64_t id) {
  if (auto wm = Win(id)) wm->PopUpWindowMenu();
}

}  // extern "C"
