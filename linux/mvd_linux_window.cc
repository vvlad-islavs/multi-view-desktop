#include "mvd_linux_window.h"

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
  auto* gdk = GetGdkWindow(window);
  if (gdk) {
    gdk_window_set_geometry_hints(gdk, &geometry, hints);
  }
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
  auto* gdk = GetGdkWindow(window);
  if (gdk) {
    gdk_window_set_geometry_hints(gdk, &geometry, hints);
  }
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
  auto* gdk = GetGdkWindow(window);
  if (gdk) {
    gdk_window_set_geometry_hints(gdk, &geometry, hints);
  }
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
    gtk_window_set_geometry_hints(window, nullptr, &geometry, hints);
    gtk_window_set_resizable(window, true);
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

void MvdLinuxWindow::SetTitleBarStyle(const gchar* style, bool wbv) {
  if (!window) {
    return;
  }
  window_button_visibility = wbv;
  const bool hidden = g_strcmp0(style, "hidden") == 0;
  GtkWidget* hb = HeaderBarOf(window);
  if (hb) {
    if (!hidden) {
      gtk_window_set_decorated(window, TRUE);
    }
    gtk_widget_set_visible(hb, !hidden);
    if (GTK_IS_HEADER_BAR(hb)) {
      if (wbv) {
        gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(hb), nullptr);
        gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), TRUE);
      } else {
        gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(hb), ":");
        gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(hb), FALSE);
      }
    }
  } else {
    gtk_window_set_decorated(window, !hidden);
  }
  if (title_bar_style) {
    g_free(title_bar_style);
  }
  title_bar_style = g_strdup(style);
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
  return window ? gtk_widget_get_opacity(GTK_WIDGET(window)) : 1.0;
}

void MvdLinuxWindow::SetOpacity(double o) {
  if (window) {
    gtk_widget_set_opacity(GTK_WIDGET(window), o);
  }
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
