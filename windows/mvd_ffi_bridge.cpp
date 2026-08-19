// MVD FFI bridge: C ABI called from Dart `FfiBridge`.
// Dart UI isolate == Win32 UI thread; no dispatch hop.

#include "include/multi_view_desktop/multi_view_desktop.h"
#include "multi_view_desktop.h"
#include "mvd_windows_taskbar_menu.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr int kStrCap = 8192;

double g_rect_buf[4] = {0, 0, 0, 0};
char g_str_buf[kStrCap] = {};
char g_str_buf2[kStrCap] = {};
int32_t g_i32_buf[8] = {};
flutter::EncodableList g_pending_menu;

void ClearRectBuf() {
  g_rect_buf[0] = 0;
  g_rect_buf[1] = 0;
  g_rect_buf[2] = 0;
  g_rect_buf[3] = 0;
}

double ScaleForWindow(multi_view_desktop::MultiViewDesktop* window) {
  const double scale = window->pixel_ratio_;
  return scale > 0 ? scale : 1.0;
}

UINT DpiForMonitor(HMONITOR monitor) {
  using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
  static GetDpiForMonitorFn fn = []() -> GetDpiForMonitorFn {
    HMODULE module = LoadLibraryW(L"shcore.dll");
    return module ? reinterpret_cast<GetDpiForMonitorFn>(
                        GetProcAddress(module, "GetDpiForMonitor"))
                  : nullptr;
  }();
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  if (fn) {
    fn(monitor, 0, &dpi_x, &dpi_y);
  }
  return dpi_x;
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

struct MonitorEnumCtx {
  double qx, qy, qw, qh, best_area, best_x, best_y, best_w, best_h;
  bool found;
};

BOOL CALLBACK EnumMonitorsForDisplayRect(HMONITOR monitor, HDC, LPRECT,
                                         LPARAM lparam) {
  auto* ctx = reinterpret_cast<MonitorEnumCtx*>(lparam);
  MONITORINFO info{};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &info)) {
    return TRUE;
  }
  const double scale = DpiForMonitor(monitor) / 96.0;
  const RECT& work = info.rcWork;
  const double x = work.left / scale;
  const double y = work.top / scale;
  const double w = (work.right - work.left) / scale;
  const double h = (work.bottom - work.top) / scale;
  const double area =
      OverlapArea(ctx->qx, ctx->qy, ctx->qw, ctx->qh, x, y, w, h);
  if (!ctx->found || area >= ctx->best_area) {
    ctx->found = true;
    ctx->best_area = area;
    ctx->best_x = x;
    ctx->best_y = y;
    ctx->best_w = w;
    ctx->best_h = h;
  }
  return TRUE;
}

using EV = flutter::EncodableValue;
using EM = flutter::EncodableMap;

multi_view_desktop::MultiViewDesktop* Win(int64_t id) {
  return multi_view_desktop::MultiViewDesktop::Instance().FindByViewId(id);
}

EM M(const char* k, EV v) { return {{EV(k), std::move(v)}}; }

EM SizeArgs(double w, double h) {
  return {{EV("width"), EV(w)}, {EV("height"), EV(h)}};
}

using MvdEventCallback = void (*)(const char*, int64_t, int64_t);
MvdEventCallback g_event_cb = nullptr;

}  // namespace

extern "C" {

FLUTTER_PLUGIN_EXPORT void mvd_set_event_callback(MvdEventCallback cb) {
  g_event_cb = cb;
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_emit_event(const char* event_name,
                                             int64_t view_id, int64_t arg) {
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
                                             int64_t parent_id) {
  EM args = {
      {EV("token"), EV(token)},
      {EV("width"), EV(w)},
      {EV("height"), EV(h)},
      {EV("title"), EV(std::string(g_str_buf))},
      {EV("titleBarStyle"), EV(std::string(g_str_buf2))},
      {EV("windowButtonVisibility"), EV(buttons != 0)},
  };
  if (has_pos) {
    args[EV("position")] = EV(EM{{EV("x"), EV(x)}, {EV("y"), EV(y)}});
  }
  if (parent_id >= 0) {
    args[EV("parentId")] = EV(parent_id);
  }
  return multi_view_desktop::MultiViewDesktop::Instance().CreateSecondaryWindow(args);
}

FLUTTER_PLUGIN_EXPORT int64_t mvd_create_modal_dialog(
    int64_t token, int64_t parent_id, double w, double h, int32_t modal,
    int32_t buttons, int32_t has_pos, double x, double y) {
  EM args = {
      {EV("token"), EV(token)},
      {EV("parentId"), EV(parent_id)},
      {EV("width"), EV(w)},
      {EV("height"), EV(h)},
      {EV("modal"), EV(modal != 0)},
      {EV("title"), EV(std::string(g_str_buf))},
      {EV("titleBarStyle"), EV(std::string(g_str_buf2))},
      {EV("windowButtonVisibility"), EV(buttons != 0)},
  };
  if (has_pos) {
    args[EV("position")] = EV(EM{{EV("x"), EV(x)}, {EV("y"), EV(y)}});
  }
  return multi_view_desktop::MultiViewDesktop::Instance().CreateModalDialogWindow(args);
}

FLUTTER_PLUGIN_EXPORT int64_t mvd_create_popup(int64_t token, int64_t parent_id,
                                            double w, double h) {
  EM args = {
      {EV("token"), EV(token)},
      {EV("parentId"), EV(parent_id)},
      {EV("width"), EV(w)},
      {EV("height"), EV(h)},
  };
  return multi_view_desktop::MultiViewDesktop::Instance().CreatePopupWindow(args);
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_check_exist(int64_t view_id) {
  return Win(view_id) ? 1 : 0;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_anchor_view_id(int64_t view_id) {
  multi_view_desktop::MultiViewDesktop::main_view_id_ = view_id;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_terminate_after_last(int32_t terminate) {
  multi_view_desktop::MultiViewDesktop::terminate_after_last_window_closed_ =
      terminate != 0;
}

FLUTTER_PLUGIN_EXPORT void mvd_reply_terminate(int32_t) {}
FLUTTER_PLUGIN_EXPORT void mvd_set_has_taskbar_callback(int32_t) {}

FLUTTER_PLUGIN_EXPORT int32_t mvd_is_hide_app_from_taskbar() {
  auto& impl = multi_view_desktop::MultiViewDesktop::Instance();
  if (impl.windows_.empty()) {
    return 1;
  }
  for (const auto& entry : impl.windows_) {
    if (!entry.second->IsSkipTaskbar()) {
      return 0;
    }
  }
  return 1;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_progress_bar(double progress) {
  auto* window = multi_view_desktop::MultiViewDesktop::Instance().FindByViewId(
      multi_view_desktop::MultiViewDesktop::Instance().main_view_id());
  if (window) {
    window->SetProgressBar(progress);
  }
}

FLUTTER_PLUGIN_EXPORT void mvd_taskbar_menu_clear() { g_pending_menu.clear(); }

FLUTTER_PLUGIN_EXPORT void mvd_taskbar_menu_add(int32_t id) {
  EM item = {{EV("id"), EV(id)}, {EV("title"), EV(std::string(g_str_buf))}};
  if (g_str_buf2[0] != 0) {
    item[EV("icon")] = EV(std::string(g_str_buf2));
  }
  g_pending_menu.push_back(EV(item));
}

FLUTTER_PLUGIN_EXPORT void mvd_taskbar_menu_commit() {
  EV list(g_pending_menu);
  multi_view_desktop::MvdWindowsSetTaskbarMenu(&list);
  g_pending_menu.clear();
}

FLUTTER_PLUGIN_EXPORT void mvd_get_frame(int64_t view_id) {
  auto* window = Win(view_id);
  if (!window) {
    ClearRectBuf();
    return;
  }
  HWND hwnd = window->GetMainWindow();
  RECT rect{};
  if (!hwnd || !GetWindowRect(hwnd, &rect)) {
    ClearRectBuf();
    return;
  }
  const double scale = ScaleForWindow(window);
  g_rect_buf[0] = static_cast<double>(rect.left) / scale;
  g_rect_buf[1] = static_cast<double>(rect.top) / scale;
  g_rect_buf[2] = static_cast<double>(rect.right - rect.left) / scale;
  g_rect_buf[3] = static_cast<double>(rect.bottom - rect.top) / scale;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_frame(int64_t view_id, double x, double y,
                                         double w, double h) {
  auto* window = Win(view_id);
  if (!window) {
    return;
  }
  window->SetPopupBounds(EM{
      {EV("x"), EV(x)},
      {EV("y"), EV(y)},
      {EV("width"), EV(w)},
      {EV("height"), EV(h)},
  });
}

FLUTTER_PLUGIN_EXPORT void mvd_get_display_rect(double x, double y, double w,
                                                double h) {
  MonitorEnumCtx ctx{};
  ctx.qx = x;
  ctx.qy = y;
  ctx.qw = w;
  ctx.qh = h;
  ctx.best_area = -1;
  ctx.found = false;
  EnumDisplayMonitors(nullptr, nullptr, EnumMonitorsForDisplayRect,
                      reinterpret_cast<LPARAM>(&ctx));
  if (!ctx.found) {
    g_rect_buf[0] = 0;
    g_rect_buf[1] = 0;
    g_rect_buf[2] = 2560;
    g_rect_buf[3] = 1440;
    return;
  }
  g_rect_buf[0] = ctx.best_x;
  g_rect_buf[1] = ctx.best_y;
  g_rect_buf[2] = ctx.best_w;
  g_rect_buf[3] = ctx.best_h;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_size(int64_t id, double w, double h) {
  if (auto* window = Win(id)) window->SetSize(SizeArgs(w, h));
}
FLUTTER_PLUGIN_EXPORT void mvd_set_position(int64_t id, double x, double y) {
  if (auto* window = Win(id))
    window->SetPosition(EM{{EV("x"), EV(x)}, {EV("y"), EV(y)}});
}
FLUTTER_PLUGIN_EXPORT void mvd_set_min_size(int64_t id, double w, double h) {
  if (auto* window = Win(id)) window->SetMinimumSize(SizeArgs(w, h));
}
FLUTTER_PLUGIN_EXPORT void mvd_set_max_size(int64_t id, double w, double h) {
  if (auto* window = Win(id)) window->SetMaximumSize(SizeArgs(w, h));
}

FLUTTER_PLUGIN_EXPORT void mvd_set_background_color(int64_t id, int32_t a,
                                                    int32_t r, int32_t g,
                                                    int32_t b) {
  if (auto* window = Win(id))
    window->SetBackgroundColor(EM{
        {EV("backgroundColorA"), EV(a)},
        {EV("backgroundColorR"), EV(r)},
        {EV("backgroundColorG"), EV(g)},
        {EV("backgroundColorB"), EV(b)},
    });
}

FLUTTER_PLUGIN_EXPORT void mvd_set_title(int64_t id) {
  if (auto* window = Win(id))
    window->SetTitle(M("title", EV(std::string(g_str_buf))));
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_title(int64_t id) {
  auto* window = Win(id);
  if (!window) return 0;
  const std::string title = window->GetTitle();
  std::strncpy(g_str_buf, title.c_str(), kStrCap - 1);
  g_str_buf[kStrCap - 1] = 0;
  return 1;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_title_bar_style(int64_t id, int32_t close_v,
                                                   int32_t, int32_t) {
  if (auto* window = Win(id))
    window->SetTitleBarStyle(EM{
        {EV("titleBarStyle"), EV(std::string(g_str_buf))},
        {EV("windowButtonVisibility"), EV(close_v != 0)},
    });
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_title_bar_style(int64_t id) {
  auto* window = Win(id);
  if (!window) return 0;
  const auto map = window->GetTitleBarStyle();
  const auto style = map.find(EV("style"));
  std::string name = "normal";
  if (style != map.end()) {
    if (const auto* s = std::get_if<std::string>(&style->second)) name = *s;
  }
  std::strncpy(g_str_buf, name.c_str(), kStrCap - 1);
  g_str_buf[kStrCap - 1] = 0;
  bool vis = true;
  const auto it = map.find(EV("windowButtonVisibility"));
  if (it != map.end()) {
    if (const auto* b = std::get_if<bool>(&it->second)) vis = *b;
  }
  g_i32_buf[0] = vis ? 1 : 0;
  g_i32_buf[1] = vis ? 1 : 0;
  g_i32_buf[2] = vis ? 1 : 0;
  return 1;
}

FLUTTER_PLUGIN_EXPORT void mvd_set_as_frameless(int64_t id) {
  if (auto* window = Win(id)) window->SetAsFrameless();
}
FLUTTER_PLUGIN_EXPORT void mvd_set_always_on_top(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetAlwaysOnTop(M("isAlwaysOnTop", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_always_on_top(int64_t id) {
  auto* window = Win(id);
  return window && window->IsAlwaysOnTop() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_full_screen(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetFullScreen(M("isFullScreen", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_full_screen(int64_t id) {
  auto* window = Win(id);
  return window && window->IsFullScreen() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_hide_app_from_taskbar(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetSkipTaskbar(M("isHideAppFromTaskbar", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_hide_app_tab_from_taskbar(int64_t id) {
  auto* window = Win(id);
  return window && window->IsSkipTaskbar() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_close_window(int64_t id) {
  if (auto* window = Win(id)) window->Close();
}
FLUTTER_PLUGIN_EXPORT void mvd_destroy_window(int64_t id) {
  multi_view_desktop::MultiViewDesktop::Instance().DestroyEntry(id);
}
FLUTTER_PLUGIN_EXPORT void mvd_focus(int64_t id) {
  if (auto* window = Win(id)) window->Focus();
}
FLUTTER_PLUGIN_EXPORT void mvd_blur(int64_t id) {
  if (auto* window = Win(id)) window->Blur();
}
FLUTTER_PLUGIN_EXPORT void mvd_set_pre_confirm(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetPreConfirmClose(M("preConfirmClose", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT void mvd_set_confirm(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetConfirmClose(M("confirmClose", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT void mvd_set_prevent_close(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetPreventClose(M("isPreventClose", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_prevent_close(int64_t id) {
  auto* window = Win(id);
  return window && window->IsPreventClose() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_brightness(int64_t id) {
  if (auto* window = Win(id))
    window->SetBrightness(M("brightness", EV(std::string(g_str_buf))));
}
FLUTTER_PLUGIN_EXPORT void mvd_set_opacity(int64_t id, double o) {
  if (auto* window = Win(id)) window->SetOpacity(M("opacity", EV(o)));
}
FLUTTER_PLUGIN_EXPORT double mvd_get_opacity(int64_t id) {
  auto* window = Win(id);
  return window ? window->GetOpacity() : 1.0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_has_shadow(int64_t id) {
  auto* window = Win(id);
  return !window || window->HasShadow() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_has_shadow(int64_t id, int32_t v) {
  if (auto* window = Win(id)) window->SetHasShadow(M("hasShadow", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT void mvd_set_aspect_ratio(int64_t id, double r) {
  if (auto* window = Win(id)) window->SetAspectRatio(M("aspectRatio", EV(r)));
}
FLUTTER_PLUGIN_EXPORT void mvd_show(int64_t id) {
  if (auto* window = Win(id)) window->Show();
}
FLUTTER_PLUGIN_EXPORT void mvd_hide(int64_t id) {
  if (auto* window = Win(id)) window->Hide();
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_visible(int64_t id) {
  auto* window = Win(id);
  return !window || window->IsVisible() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_focused(int64_t id) {
  auto* window = Win(id);
  return window && window->IsFocused() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_on_active_space(int64_t) { return 1; }
FLUTTER_PLUGIN_EXPORT void mvd_maximize(int64_t id, int32_t vertically) {
  if (auto* window = Win(id))
    window->Maximize(M("vertically", EV(vertically != 0)));
}
FLUTTER_PLUGIN_EXPORT void mvd_unmaximize(int64_t id) {
  if (auto* window = Win(id)) window->Unmaximize();
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_maximized(int64_t id) {
  auto* window = Win(id);
  return window && window->IsMaximized() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_minimize(int64_t id) {
  if (auto* window = Win(id)) window->Minimize();
}
FLUTTER_PLUGIN_EXPORT void mvd_restore(int64_t id) {
  if (auto* window = Win(id)) window->Restore();
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_minimized(int64_t id) {
  auto* window = Win(id);
  return window && window->IsMinimized() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_resizable(int64_t id) {
  auto* window = Win(id);
  return !window || window->IsResizable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_resizable(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetResizable(M("isResizable", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_movable(int64_t id) {
  auto* window = Win(id);
  return !window || window->IsMovable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_movable(int64_t id, int32_t v) {
  if (auto* window = Win(id)) window->SetMovable(M("isMovable", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_minimizable(int64_t id) {
  auto* window = Win(id);
  return !window || window->IsMinimizable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_minimizable(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetMinimizable(M("isMinimizable", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_maximizable(int64_t id) {
  auto* window = Win(id);
  return !window || window->IsMaximizable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_maximizable(int64_t id, int32_t v) {
  if (auto* window = Win(id))
    window->SetMaximizable(M("isMaximizable", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_closable(int64_t id) {
  auto* window = Win(id);
  return !window || window->IsClosable() ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_set_closable(int64_t id, int32_t v) {
  if (auto* window = Win(id)) window->SetClosable(M("isClosable", EV(v != 0)));
}
FLUTTER_PLUGIN_EXPORT void mvd_start_dragging(int64_t id) {
  if (auto* window = Win(id)) window->StartDragging();
}
FLUTTER_PLUGIN_EXPORT void mvd_start_resizing(int64_t id, int32_t t, int32_t b,
                                              int32_t l, int32_t r) {
  if (auto* window = Win(id))
    window->StartResizing(EM{
        {EV("top"), EV(t != 0)},
        {EV("bottom"), EV(b != 0)},
        {EV("left"), EV(l != 0)},
        {EV("right"), EV(r != 0)},
    });
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
                                                       int32_t) {
  if (auto* window = Win(id))
    window->SetIgnoreMouseEvents(M("ignore", EV(ignore != 0)));
}
FLUTTER_PLUGIN_EXPORT int32_t mvd_is_ignore_mouse_events(int64_t id) {
  auto* window = Win(id);
  g_i32_buf[0] = 0;
  if (!window) return 0;
  const auto map = window->IsIgnoreMouseEvents();
  const auto it = map.find(EV("ignore"));
  bool ignore = false;
  if (it != map.end()) {
    if (const auto* b = std::get_if<bool>(&it->second)) ignore = *b;
  }
  return ignore ? 1 : 0;
}
FLUTTER_PLUGIN_EXPORT void mvd_pop_up_window_menu(int64_t id) {
  if (auto* window = Win(id)) window->PopUpWindowMenu(EM{});
}

}  // extern "C"
