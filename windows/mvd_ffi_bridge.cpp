// MVD FFI bridge — C ABI called from Dart `FfiBridge`.
// Dart UI isolate == Win32 UI thread; no dispatch hop.
//
// Symbol convention: mvd_<verb>_<noun>
// Shared output buffer: mvd_rect_buf_ptr → Double[4] = {x, y, w, h}

#include "include/multi_view_desktop/multi_view_desktop.h"
#include "multi_view_desktop.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace {

double g_rect_buf[4] = {0, 0, 0, 0};

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
  double qx;
  double qy;
  double qw;
  double qh;
  double best_area;
  double best_x;
  double best_y;
  double best_w;
  double best_h;
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

}  // namespace

extern "C" {

// MARK: Shared rect buffer

FLUTTER_PLUGIN_EXPORT double* mvd_rect_buf_ptr() { return g_rect_buf; }

// MARK: Window

FLUTTER_PLUGIN_EXPORT void mvd_get_frame(int64_t view_id) {
  auto* window =
      multi_view_desktop::MultiViewDesktop::Instance().FindByViewId(view_id);
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
  auto* window =
      multi_view_desktop::MultiViewDesktop::Instance().FindByViewId(view_id);
  if (!window) {
    return;
  }
  HWND hwnd = window->GetMainWindow();
  if (!hwnd) {
    return;
  }
  const double scale = ScaleForWindow(window);
  const int left = static_cast<int>(x * scale);
  const int top = static_cast<int>(y * scale);
  const int width = static_cast<int>(w * scale);
  const int height = static_cast<int>(h * scale);

  RECT current{};
  GetWindowRect(hwnd, &current);
  const int cur_w = current.right - current.left;
  const int cur_h = current.bottom - current.top;
  const bool size_changed =
      std::abs((cur_w / scale) - w) > 0.5 || std::abs((cur_h / scale) - h) > 0.5;

  UINT flags = SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE;
  if (!size_changed) {
    flags |= SWP_NOSIZE;
  }
  SetWindowPos(hwnd, nullptr, left, top, width, height, flags);
}

FLUTTER_PLUGIN_EXPORT void mvd_set_ignore_mouse_events(int64_t view_id,
                                                       int32_t ignore) {
  auto* window =
      multi_view_desktop::MultiViewDesktop::Instance().FindByViewId(view_id);
  if (!window) {
    return;
  }
  HWND hwnd = window->GetMainWindow();
  if (!hwnd) {
    return;
  }
  LONG ex_style = ::GetWindowLong(hwnd, GWL_EXSTYLE);
  if (ignore) {
    ex_style |= (WS_EX_TRANSPARENT | WS_EX_LAYERED);
  } else {
    ex_style &= ~(WS_EX_TRANSPARENT | WS_EX_LAYERED);
  }
  ::SetWindowLong(hwnd, GWL_EXSTYLE, ex_style);
}

// MARK: Display

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

}  // extern "C"
