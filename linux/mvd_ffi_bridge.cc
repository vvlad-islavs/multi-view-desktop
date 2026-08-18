// MVD FFI bridge — C ABI called from Dart `FfiBridge`.
// Dart UI isolate == GTK main thread; no dispatch hop.
//
// Symbol convention: mvd_<verb>_<noun>
// Shared output buffer: mvd_rect_buf_ptr → Double[4] = {x, y, w, h}

#include "mvd_linux_window.h"

#include <gtk/gtk.h>

#include <algorithm>
#include <cmath>
#include <cstdint>

#include <multiview_desktop/multiview_desktop_plugin.h>

namespace {

double g_rect_buf[4] = {0, 0, 0, 0};

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

}  // namespace

extern "C" {

// Shared rect buffer

FLUTTER_PLUGIN_EXPORT double* mvd_rect_buf_ptr() { return g_rect_buf; }

// Window

FLUTTER_PLUGIN_EXPORT void mvd_get_frame(int64_t view_id) {
  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm || !wm->window) {
    ClearRectBuf();
    return;
  }
  gint x = 0;
  gint y = 0;
  gint width = 0;
  gint height = 0;
  gtk_window_get_position(wm->window, &x, &y);
  gtk_window_get_size(wm->window, &width, &height);
  g_rect_buf[0] = static_cast<double>(x);
  g_rect_buf[1] = static_cast<double>(y);
  g_rect_buf[2] = static_cast<double>(width);
  g_rect_buf[3] = static_cast<double>(height);
}

FLUTTER_PLUGIN_EXPORT void mvd_set_frame(int64_t view_id, double x, double y,
                                         double w, double h) {
  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm || !wm->window) {
    return;
  }
  gint cur_w = 0;
  gint cur_h = 0;
  gtk_window_get_size(wm->window, &cur_w, &cur_h);
  const gint width = static_cast<gint>(w);
  const gint height = static_cast<gint>(h);
  gtk_window_move(wm->window, static_cast<gint>(x), static_cast<gint>(y));
  if (std::abs(cur_w - w) > 0.5 || std::abs(cur_h - h) > 0.5) {
    gtk_window_resize(wm->window, width, height);
  }
}

FLUTTER_PLUGIN_EXPORT void mvd_set_ignore_mouse_events(int64_t view_id,
                                                       int32_t ignore) {
  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm) {
    return;
  }
  wm->SetIgnoreMouseEvents(ignore != 0, false);
}

// Display

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
  double best_area = -1;
  double best_x = 0;
  double best_y = 0;
  double best_w = 2560;
  double best_h = 1440;
  bool found = false;

  for (int i = 0; i < n; i++) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (!monitor) {
      continue;
    }
    GdkRectangle work{};
    gdk_monitor_get_workarea(monitor, &work);
    const double mx = static_cast<double>(work.x);
    const double my = static_cast<double>(work.y);
    const double mw = static_cast<double>(work.width);
    const double mh = static_cast<double>(work.height);
    const double area = OverlapArea(x, y, w, h, mx, my, mw, mh);
    if (!found || area >= best_area) {
      found = true;
      best_area = area;
      best_x = mx;
      best_y = my;
      best_w = mw;
      best_h = mh;
    }
  }

  g_rect_buf[0] = best_x;
  g_rect_buf[1] = best_y;
  g_rect_buf[2] = best_w;
  g_rect_buf[3] = best_h;
}

}  // extern "C"
