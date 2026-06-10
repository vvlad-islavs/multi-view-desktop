#include "mvd_linux_window.h"
#include <gtk/gtk.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstring>

std::mutex MvdLinuxWindow::registry_mtx;
std::map<int64_t, std::shared_ptr<MvdLinuxWindow>> MvdLinuxWindow::windows;

MvdLinuxWindow::MvdLinuxWindow() {
  geometry.min_width = -1;
  geometry.min_height = -1;
  geometry.max_width = G_MAXINT;
  geometry.max_height = G_MAXINT;
}

MvdLinuxWindow::~MvdLinuxWindow() {
  if (css_provider) {
    g_object_unref(css_provider);
  }
  if (csd_radius_provider) {
    g_object_unref(csd_radius_provider);
  }
  if (title_bar_style) {
    g_free(title_bar_style);
  }
}

GdkWindow* MvdLinuxWindow::GetGdkWindow(GtkWindow* w) {
  if (!w) {
    return nullptr;
  }
  return gtk_widget_get_window(GTK_WIDGET(w));
}

GtkWidget* MvdLinuxWindow::HeaderBarOf(GtkWindow* w) {
  GtkWidget* titlebar = gtk_window_get_titlebar(w);
  if (titlebar &&
      (GTK_IS_HEADER_BAR(titlebar) ||
       g_str_has_suffix(G_OBJECT_TYPE_NAME(titlebar), "HeaderBar"))) {
    return titlebar;
  }
  return nullptr;
}

FlValue* MvdLinuxWindow::MakeBounds(GtkWindow* w) {
  gint x = 0;
  gint y = 0;
  gint width = 0;
  gint height = 0;
  gtk_window_get_position(w, &x, &y);
  gtk_window_get_size(w, &width, &height);
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  fl_value_set_string_take(map, "width", fl_value_new_float(width));
  fl_value_set_string_take(map, "height", fl_value_new_float(height));
  return map;
}

std::shared_ptr<MvdLinuxWindow> MvdLinuxWindow::Find(int64_t view_id) {
  std::lock_guard<std::mutex> lock(registry_mtx);
  auto it = windows.find(view_id);
  return it == windows.end() ? nullptr : it->second;
}

void MvdLinuxWindow::Unregister(int64_t view_id) {
  std::lock_guard<std::mutex> lock(registry_mtx);
  windows.erase(view_id);
}

void MvdLinuxWindow::SetAsFrameless() {
  if (!window) {
    return;
  }
  // Hide the header bar when using client-side decorations.
  GtkWidget* hb = HeaderBarOf(window);
  if (hb) {
    gtk_widget_set_visible(hb, FALSE);
  }
  gtk_window_set_decorated(window, FALSE);
  ReapplyGeometryHints();
}

void MvdLinuxWindow::Close() {
  if (!window) {
    return;
  }
  auto* vid = new int64_t(view_id);
  g_idle_add(
      [](gpointer data) -> gboolean {
        std::unique_ptr<int64_t> p(static_cast<int64_t*>(data));
        auto wm = MvdLinuxWindow::Find(*p);
        if (wm && wm->window) {
          gtk_window_close(wm->window);
        }
        return G_SOURCE_REMOVE;
      },
      vid);
}

void MvdLinuxWindow::Focus() {
  if (window) {
    gtk_window_present(window);
  }
}

bool MvdLinuxWindow::IsFocused() {
  return window ? gtk_window_is_active(window) : false;
}

void MvdLinuxWindow::Show() {
  if (!window) {
    return;
  }
  gtk_widget_show(GTK_WIDGET(window));
  gtk_window_present(window);
}

void MvdLinuxWindow::Hide() {
  if (!window) {
    return;
  }
  gint x = 0;
  gint y = 0;
  gint w = 0;
  gint h = 0;
  gtk_window_get_position(window, &x, &y);
  gtk_window_get_size(window, &w, &h);
  gtk_widget_hide(GTK_WIDGET(window));
  gtk_window_move(window, x, y);
  gtk_window_resize(window, w, h);
}

bool MvdLinuxWindow::IsVisible() {
  return window ? gtk_widget_is_visible(GTK_WIDGET(window)) : false;
}

bool MvdLinuxWindow::IsMaximized() {
  return window ? gtk_window_is_maximized(window) : false;
}

void MvdLinuxWindow::Maximize() {
  if (window) {
    gtk_window_maximize(window);
  }
}

void MvdLinuxWindow::Unmaximize() {
  if (window) {
    gtk_window_unmaximize(window);
  }
}

bool MvdLinuxWindow::IsMinimized() {
  if (!window) {
    return false;
  }
  auto* gdk = GetGdkWindow(window);
  return gdk ? (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_ICONIFIED) != 0
             : false;
}

void MvdLinuxWindow::Minimize() {
  if (window) {
    gtk_window_iconify(window);
  }
}

void MvdLinuxWindow::Restore() {
  if (!window) {
    return;
  }
  gtk_window_deiconify(window);
  gtk_window_present(window);
}

bool MvdLinuxWindow::IsFullScreen() {
  if (!window) {
    return false;
  }
  auto* gdk = GetGdkWindow(window);
  return gdk ? (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_FULLSCREEN) != 0
             : false;
}

void MvdLinuxWindow::SetFullScreen(bool fs) {
  if (!window) {
    return;
  }
  is_fullscreen = fs;
  if (fs) {
    gtk_window_fullscreen(window);
  } else {
    gtk_window_unfullscreen(window);
  }
}

void MvdLinuxWindow::SetAspectRatio(float ar) {
  if (!window) {
    return;
  }
  geometry.min_aspect = ar;
  geometry.max_aspect = ar;
  if (ar >= 0) {
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_ASPECT);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_ASPECT);
  }
  ReapplyGeometryHints();
}

bool MvdLinuxWindow::SetBackgroundColor(int r, int g, int b, int a) {
  if (!window) {
    return false;
  }
  GdkRGBA rgba;
  rgba.red = r / 255.0;
  rgba.green = g / 255.0;
  rgba.blue = b / 255.0;
  rgba.alpha = a / 255.0;
  g_autofree gchar* color = gdk_rgba_to_string(&rgba);
  g_autofree gchar* css =
      g_strdup_printf("window { background-color: %s; }", color);
  if (!css_provider) {
    css_provider = gtk_css_provider_new();
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(GTK_WIDGET(window)),
        GTK_STYLE_PROVIDER(css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }
  g_autoptr(GError) error = nullptr;
  gtk_css_provider_load_from_data(css_provider, css, -1, &error);
  return error == nullptr;
}

FlValue* MvdLinuxWindow::GetBounds() {
  if (!window) {
    return nullptr;
  }
  return MakeBounds(window);
}

void MvdLinuxWindow::SetBounds(FlValue* args) {
  if (!window || !args) {
    return;
  }
  FlValue* x = fl_value_lookup_string(args, "x");
  FlValue* y = fl_value_lookup_string(args, "y");
  if (x && y) {
    gtk_window_move(window, static_cast<gint>(fl_value_get_float(x)),
                    static_cast<gint>(fl_value_get_float(y)));
  }
  FlValue* w = fl_value_lookup_string(args, "width");
  FlValue* h = fl_value_lookup_string(args, "height");
  if (w && h) {
    gtk_window_resize(window, static_cast<gint>(fl_value_get_float(w)),
                      static_cast<gint>(fl_value_get_float(h)));
  }
}

void MvdLinuxWindow::SetSize(double width, double height) {
  if (!window) {
    return;
  }
  gtk_window_resize(window, static_cast<gint>(width), static_cast<gint>(height));
}

void MvdLinuxWindow::SetPosition(double x, double y) {
  if (window) {
    gtk_window_move(window, static_cast<gint>(x), static_cast<gint>(y));
  }
}

void MvdLinuxWindow::Center() {
  if (window) {
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  }
}

void MvdLinuxWindow::RefreshShadowCache() {
  // Only measure the CSD shadow in the normal (non-maximized, non-fullscreen)
  // state. In maximized/fullscreen GTK suppresses the shadow, so the delta
  // would be 0 — which would wrongly overwrite a valid cached value.
  if (!window || gtk_window_is_maximized(window) || is_fullscreen) {
    return;
  }
  GdkWindow* gdk = GetGdkWindow(window);
  if (!gdk) {
    return;
  }
  gint gdk_w = gdk_window_get_width(gdk);
  gint gdk_h = gdk_window_get_height(gdk);
  gint gtk_w = 0, gtk_h = 0;
  gtk_window_get_size(window, &gtk_w, &gtk_h);
  const gint sw = (gdk_w > gtk_w) ? (gdk_w - gtk_w) : 0;
  const gint sh = (gdk_h > gtk_h) ? (gdk_h - gtk_h) : 0;

  // Re-apply hints only when the cache value actually changes (first non-zero
  // measurement, or if the shadow size changes due to theme switching).
  const bool changed = (sw > 0 && sw != cached_shadow_w) ||
                       (sh > 0 && sh != cached_shadow_h);
  if (sw > 0) { cached_shadow_w = sw; }
  if (sh > 0) { cached_shadow_h = sh; }
  if (changed && hints != static_cast<GdkWindowHints>(0)) {
    ReapplyGeometryHints();
  }
}

void MvdLinuxWindow::ReapplyGeometryHints() {
  if (!window || hints == static_cast<GdkWindowHints>(0)) {
    return;
  }

  // Use the cached shadow delta measured by RefreshShadowCache() during normal
  // window state. This avoids any live measurement here so that the function
  // works correctly regardless of the current window state (maximized,
  // fullscreen, mid-transition). RefreshShadowCache() is called from
  // on_configure (fires in every normal-state resize) and keeps the cache
  // up-to-date without touching hints on every frame.
  //
  // On Wayland or when the window is frameless the cache stays 0, which is
  // correct because the compositor uses surface-area coordinates directly.
  GdkGeometry effective = geometry;
  if (cached_shadow_w > 0 || cached_shadow_h > 0) {
    if ((hints & GDK_HINT_MIN_SIZE) && geometry.min_width >= 0) {
      effective.min_width  = geometry.min_width  + cached_shadow_w;
      effective.min_height = geometry.min_height + cached_shadow_h;
    }
    if ((hints & GDK_HINT_MAX_SIZE) && geometry.max_width < G_MAXINT) {
      effective.max_width  = geometry.max_width  + cached_shadow_w;
      effective.max_height = geometry.max_height + cached_shadow_h;
    }
  }

  gtk_window_set_geometry_hints(window, nullptr, &effective, hints);
  gtk_widget_queue_resize(GTK_WIDGET(window));
}

void MvdLinuxWindow::SetMinimumSize(float w, float h) {
  if (!window) {
    return;
  }
  if (w >= 0 && h >= 0) {
    geometry.min_width = static_cast<gint>(w);
    geometry.min_height = static_cast<gint>(h);
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_MIN_SIZE);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_MIN_SIZE);
  }
  ReapplyGeometryHints();
}

void MvdLinuxWindow::SetMaximumSize(float w, float h) {
  if (!window) {
    return;
  }
  geometry.max_width = static_cast<gint>(w);
  geometry.max_height = static_cast<gint>(h);
  if (w >= 0 && h >= 0) {
    hints = static_cast<GdkWindowHints>(hints | GDK_HINT_MAX_SIZE);
  } else {
    hints = static_cast<GdkWindowHints>(hints & ~GDK_HINT_MAX_SIZE);
  }
  if (geometry.max_width < 0) {
    geometry.max_width = G_MAXINT;
  }
  if (geometry.max_height < 0) {
    geometry.max_height = G_MAXINT;
  }
  ReapplyGeometryHints();
}

bool MvdLinuxWindow::IsResizable() {
  return is_resizable;
}

void MvdLinuxWindow::SetResizable(bool v) {
  is_resizable = v;
  if (!window) {
    return;
  }
  if (!v) {
    gint w = 0, h = 0;
    gtk_window_get_size(window, &w, &h);
    if (w <= 0 || h <= 0) {
      gtk_window_set_resizable(window, false);
      return;
    }

    // set_resizable(false) resets the window to gtk_window_get_remembered_size(),
    // which falls back to gtk_window_set_default_size() from my_application.cc.
    gtk_window_set_default_size(window, w, h);

    GdkGeometry fixed{};
    fixed.min_width  = fixed.max_width  = w;
    fixed.min_height = fixed.max_height = h;
    gtk_window_set_geometry_hints(window, nullptr, &fixed,
        static_cast<GdkWindowHints>(GDK_HINT_MIN_SIZE | GDK_HINT_MAX_SIZE));

    gtk_window_resize(window, w, h);
    gtk_window_set_resizable(window, false);
  } else {
    gtk_window_set_resizable(window, true);
    ReapplyGeometryHints();
  }
}

bool MvdLinuxWindow::IsMinimizable() {
  return is_minimizable;
}

// Updates type hint and taskbar-skip hints from stored state.
void MvdLinuxWindow::ApplyWindowTypeHint() {
  if (!window) return;
  gtk_window_set_type_hint(
      window,
      is_minimizable ? GDK_WINDOW_TYPE_HINT_NORMAL : GDK_WINDOW_TYPE_HINT_DIALOG);
  gtk_window_set_skip_taskbar_hint(window, is_skip_taskbar ? TRUE : FALSE);
  gtk_window_set_skip_pager_hint(window, is_skip_taskbar ? TRUE : FALSE);
}

void MvdLinuxWindow::SetMinimizable(bool v) {
  is_minimizable = v;
  ApplyWindowTypeHint();
}

bool MvdLinuxWindow::IsMaximizable() {
  return true;
}

void MvdLinuxWindow::SetMaximizable(bool /*v*/) {
  // Same as resizable on Linux.
}

bool MvdLinuxWindow::IsClosable() {
  return window ? gtk_window_get_deletable(window) : false;
}

void MvdLinuxWindow::SetClosable(bool v) {
  if (window) {
    gtk_window_set_deletable(window, v);
  }
}

void MvdLinuxWindow::SetAlwaysOnTop(bool v) {
  if (window) {
    gtk_window_set_keep_above(window, v);
  }
}

const gchar* MvdLinuxWindow::GetTitle() {
  return window ? gtk_window_get_title(window) : "";
}

void MvdLinuxWindow::SetTitle(const gchar* t) {
  if (window) {
    gtk_window_set_title(window, t);
    GtkWidget* hb = HeaderBarOf(window);
    if (hb && GTK_IS_HEADER_BAR(hb)) {
      gtk_header_bar_set_title(GTK_HEADER_BAR(hb), t);
    }
  }
}

void MvdLinuxWindow::ClampWindowToConstraints() {
  if (!window || gtk_window_is_maximized(window) || is_fullscreen) {
    return;
  }
  if (hints == static_cast<GdkWindowHints>(0)) {
    return;
  }
  gint w = 0, h = 0;
  gtk_window_get_size(window, &w, &h);
  gint new_w = w, new_h = h;

  if ((hints & GDK_HINT_MIN_SIZE) && geometry.min_width >= 0) {
    if (new_w < geometry.min_width) { new_w = geometry.min_width; }
    if (new_h < geometry.min_height) { new_h = geometry.min_height; }
  }
  if ((hints & GDK_HINT_MAX_SIZE) && geometry.max_width < G_MAXINT) {
    if (new_w > geometry.max_width) { new_w = geometry.max_width; }
    if (new_h > geometry.max_height) { new_h = geometry.max_height; }
  }

  if (new_w != w || new_h != h) {
    gtk_window_resize(window, new_w, new_h);
  }
}

void MvdLinuxWindow::SetTitleBarStyle(const gchar* style, bool wbv) {
  if (!window) {
    return;
  }
  window_button_visibility = wbv;
  const bool hidden = g_strcmp0(style, "hidden") == 0;

  // Capture the current window size before any changes so we can restore it
  // in the idle callback (GTK auto-grows/shrinks by hb_h when toggling the
  // header bar, and gtk_window_resize in the idle corrects this).
  gint orig_w = 0, orig_h = 0;
  gtk_window_get_size(window, &orig_w, &orig_h);

  GtkWidget* hb = HeaderBarOf(window);
  gint hb_h = 0;
  if (hb && !gtk_window_is_maximized(window) && !is_fullscreen) {
    if (hidden && gtk_widget_is_visible(hb)) {
      // Measure and persist the header bar height while it is still visible.
      // gtk_widget_get_preferred_height of a hidden widget returns 0 on some
      // GTK versions, so we cache it here for the reverse (show) direction.
      hb_h = gtk_widget_get_allocated_height(hb);
      // g_print("[MVD]   hb_h: %d\n", hb_h);
      // if (hb_h <= 1) {
        // gtk_widget_get_preferred_height(hb, nullptr, &hb_h);
      // }
      stored_hb_h = hb_h;
    } else if (!hidden && !gtk_widget_is_visible(hb)) {
      // hb_h = stored_hb_h;
    }

  }

  if (hb) {
    if (!hidden) {
      gtk_window_set_decorated(window, TRUE);
    }
    gtk_widget_set_visible(hb, !hidden);

    gint win_w_after = 0, win_h_after = 0;
    gtk_window_get_size(window, &win_w_after, &win_h_after);
    // g_print("[MVD]   after set_visible: %dx%d\n", win_w_after, win_h_after);

    if (GTK_IS_HEADER_BAR(hb)) {
      if (wbv) {
        gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(hb), nullptr);
        gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), TRUE);
      } else {
        gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(hb), ":");
        gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), FALSE);
      }
    }

    // When the header bar is hidden the CSD frame still has rounded top
    // corners, but Flutter's GL content is rectangular and protrudes past
    // them. Fix: override the CSS border-radius of the window content area
    // to 0, which makes the inner visible area square-cornered so it matches
    // Flutter's rectangular rendering. The outer shadow decoration is
    // separate and remains unchanged.
    if (!csd_radius_provider) {
      csd_radius_provider = gtk_css_provider_new();
      // Use PRIORITY_USER (800) so our rule beats the theme (PRIORITY_THEME=200)
      // and application-level providers (PRIORITY_APPLICATION=600).
      // Target both window.csd (background) and decoration (shadow/border) nodes
      // since Adwaita rounds corners on both elements independently.
      gtk_style_context_add_provider(
          gtk_widget_get_style_context(GTK_WIDGET(window)),
          GTK_STYLE_PROVIDER(csd_radius_provider),
          GTK_STYLE_PROVIDER_PRIORITY_USER);
    }
    gtk_css_provider_load_from_data(
        csd_radius_provider,
        hidden ? "window.csd { border-radius: 0; }\n"
                 "decoration { border-radius: 0; }" : "",
        -1, nullptr);

    // Clear the shadow cache: it was measured with the header bar visible and
    // includes the header bar height in the GDK-GTK delta. After toggling
    // visibility the shadow extents change; on_configure will re-measure.
    cached_shadow_w = 0;
    cached_shadow_h = 0;
  } else {
    gtk_window_set_decorated(window, !hidden);
  }
  
  ReapplyGeometryHints();

  if (title_bar_style) {
    g_free(title_bar_style);
  }
  title_bar_style = g_strdup(style);

  // After GTK's layout pass (auto-grows/shrinks the window by hb_h and shifts
  // the content position), restore the original size AND compensate the Y
  // position so visible content stays at the same screen coordinates:
  //   HIDE: content shifts UP inside surface → move surface DOWN by hb_h.
  //   SHOW: inverse — move surface UP by hb_h.
  // if (!gtk_window_is_maximized(window) && !is_fullscreen && orig_w > 0 && orig_h > 0) {
    // struct Args { MvdLinuxWindow* self; gint w, h, hb_h; bool hidden; };
    // auto* args = new Args{this, orig_w, orig_h, hb_h, hidden};
    // g_idle_add_full(
        // G_PRIORITY_LOW,
        // [](gpointer data) -> gboolean {
          // auto* a = static_cast<Args*>(data);
          // gtk_window_resize(a->self->window, a->w, a->h);
          // gint cx = 0, cy = 0;
          // gtk_window_get_position(window, &cx, &cy);
          // GtkWindowPosition position = GtkWindowPosition();
          // gtk_window_set_position(window, GTK_WIN_POS_MOUSE);
          // if (a->hb_h > 0) {
          //   gint cx = 0, cy = 0;
          //   gtk_window_get_position(a->self->window, &cx, &cy);
          //   gtk_window_move(a->self->window, cx,
          //                   cy + (a->hidden ? a->hb_h : -a->hb_h));
          // }
          // g_print("[MVD]   hb_h3: %d\n", hb_h);
          // delete a;
          // return G_SOURCE_REMOVE;
        // },
        // args, nullptr);
  // }
}


FlValue* MvdLinuxWindow::GetTitleBarStyle() {
  const char* style = title_bar_style ? title_bar_style : "normal";
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "style", fl_value_new_string(style));
  fl_value_set_string_take(map, "windowButtonVisibility",
                           fl_value_new_bool(window_button_visibility));
  return map;
}

bool MvdLinuxWindow::IsSkipTaskbar() {
  return is_skip_taskbar;
}

void MvdLinuxWindow::SetSkipTaskbar(bool v) {
  is_skip_taskbar = v;
  ApplyWindowTypeHint();
}

double MvdLinuxWindow::GetOpacity() {
  return opacity;
}

void MvdLinuxWindow::SetOpacity(double o) {
  if (!window) {
    return;
  }
  opacity = o;
  GdkWindow* gdk = GetGdkWindow(window);
  if (gdk && o < 1.0) {
    // When the window is semi-transparent the compositor must blend it with
    // whatever is behind it. If GDK has advertised an opaque region (which
    // Flutter's GL view typically does), some compositors skip the background
    // read and produce visual trails/ghosts. Clearing the opaque region
    // forces the compositor to perform proper alpha compositing.
    gdk_window_set_opaque_region(gdk, nullptr);
  }
  gtk_widget_set_opacity(GTK_WIDGET(window), o);
}

void MvdLinuxWindow::SetBrightness(const gchar* brightness) {
  const gboolean dark = g_strcmp0(brightness, "dark") == 0;
  GtkSettings* settings = gtk_settings_get_default();
  g_object_set(settings, "gtk-application-prefer-dark-theme", dark, nullptr);
}

void MvdLinuxWindow::PopUpWindowMenu() {
  if (!window) {
    return;
  }
  auto* gdk = GetGdkWindow(window);
  if (!gdk) {
    return;
  }
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  int x = 0;
  int y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  int ox = 0;
  int oy = 0;
  gdk_window_get_origin(gdk, &ox, &oy);
  GdkEvent* e = gdk_event_new(GDK_BUTTON_PRESS);
  e->button.window = gdk;
  e->button.device = pointer;
  e->button.x_root = x;
  e->button.y_root = y;
  e->button.x = x - ox;
  e->button.y = y - oy;
  gdk_window_show_window_menu(gdk, e);
  gdk_event_free(e);
}

void MvdLinuxWindow::StartDragging() {
  if (!window) {
    return;
  }
  auto* screen = gtk_window_get_screen(window);
  auto* display = gdk_screen_get_display(screen);
  auto* seat = gdk_display_get_default_seat(display);
  auto* device = gdk_seat_get_pointer(seat);
  gint rx = 0;
  gint ry = 0;
  gdk_device_get_position(device, nullptr, &rx, &ry);
  guint32 ts = static_cast<guint32>(g_get_monotonic_time());
  gtk_window_begin_move_drag(window,
                           last_button.button ? last_button.button : 1, rx,
                           ry, ts);
}

void MvdLinuxWindow::StartResizing(const gchar* edge) {
  if (!window) {
    return;
  }
  GdkWindowEdge ge = GDK_WINDOW_EDGE_NORTH_WEST;
  if (g_strcmp0(edge, "topLeft") == 0) {
    ge = GDK_WINDOW_EDGE_NORTH_WEST;
  } else if (g_strcmp0(edge, "top") == 0) {
    ge = GDK_WINDOW_EDGE_NORTH;
  } else if (g_strcmp0(edge, "topRight") == 0) {
    ge = GDK_WINDOW_EDGE_NORTH_EAST;
  } else if (g_strcmp0(edge, "left") == 0) {
    ge = GDK_WINDOW_EDGE_WEST;
  } else if (g_strcmp0(edge, "right") == 0) {
    ge = GDK_WINDOW_EDGE_EAST;
  } else if (g_strcmp0(edge, "bottomLeft") == 0) {
    ge = GDK_WINDOW_EDGE_SOUTH_WEST;
  } else if (g_strcmp0(edge, "bottom") == 0) {
    ge = GDK_WINDOW_EDGE_SOUTH;
  } else if (g_strcmp0(edge, "bottomRight") == 0) {
    ge = GDK_WINDOW_EDGE_SOUTH_EAST;
  }

  auto* screen = gtk_window_get_screen(window);
  auto* display = gdk_screen_get_display(screen);
  auto* seat = gdk_display_get_default_seat(display);
  auto* device = gdk_seat_get_pointer(seat);
  gint rx = 0;
  gint ry = 0;
  gdk_device_get_position(device, nullptr, &rx, &ry);
  guint32 ts = static_cast<guint32>(g_get_monotonic_time());
  gtk_window_begin_resize_drag(window, ge,
                               last_button.button ? last_button.button : 1,
                               rx, ry, ts);
}

bool MvdLinuxWindow::IsMovable() {
  return window ? gtk_window_get_resizable(window) : true;
}

void MvdLinuxWindow::SetMovable(bool v) {
  SetResizable(v);
}

bool MvdLinuxWindow::HasShadow() {
  return true;
}

void MvdLinuxWindow::SetHasShadow(bool v) {
  (void)v;
}

// Applies pass-through to every GDK window in the widget tree.
static void apply_pass_through(GtkWidget* widget, gboolean pass_through) {
  GdkWindow* w = gtk_widget_get_window(widget);
  if (w) {
    gdk_window_set_pass_through(w, pass_through);
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_forall(
        GTK_CONTAINER(widget),
        [](GtkWidget* child, gpointer data) {
          apply_pass_through(child, static_cast<gboolean>(GPOINTER_TO_INT(data)));
        },
        GINT_TO_POINTER(static_cast<gint>(pass_through)));
  }
}

void MvdLinuxWindow::SetIgnoreMouseEvents(bool ignore, bool forward) {
  is_ignore_mouse_events = ignore;
  is_forward_mouse_events = forward;
  if (!window) return;
  apply_pass_through(GTK_WIDGET(window), ignore ? TRUE : FALSE);
}

std::pair<bool, bool> MvdLinuxWindow::IsIgnoreMouseEvents() {
  return {is_ignore_mouse_events, is_forward_mouse_events};
}
