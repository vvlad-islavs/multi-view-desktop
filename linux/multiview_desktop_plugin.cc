#include <multiview_desktop/multiview_desktop_plugin.h>

#include "mvd_linux_internal.h"
#include "mvd_linux_window.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>

namespace {

FlMethodChannel* g_channel = nullptr;
FlMethodChannel* g_screen_channel = nullptr;
FlEventChannel* g_screen_event_channel = nullptr;
FlValue* g_screen_event_sink = nullptr;

MvdWindowCreatedCallback g_create_cb = nullptr;
gboolean g_terminate_after_last_window_closed = TRUE;
int64_t g_anchor_view_id = -1;

struct PendingCreate {
  int64_t token = 0;
  double width = 800;
  double height = 600;
  std::string title;
  std::string title_bar_style;
  bool window_button_visibility = true;
  bool has_position = false;
  double pos_x = 0;
  double pos_y = 0;
};

std::mutex g_pending_mtx;
std::map<int64_t, PendingCreate> g_pending_create;

static gpointer view_id_to_pointer(int64_t view_id) {
  return GSIZE_TO_POINTER(static_cast<gsize>(view_id));
}

static int64_t pointer_to_view_id(gpointer data) {
  return static_cast<int64_t>(GPOINTER_TO_SIZE(data));
}

static int64_t int64_from_map(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return 0;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_INT) {
    return 0;
  }
  return fl_value_get_int(v);
}

static double double_from_map(FlValue* args, const char* key, double fallback) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v) {
    return fallback;
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(v);
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(v));
  }
  return fallback;
}

static bool bool_from_map(FlValue* args, const char* key, bool fallback) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(v);
}

static const char* string_from_map(FlValue* args, const char* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "";
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (!v || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) {
    return "";
  }
  return fl_value_get_string(v);
}

static FlMethodResponse* ok_null() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* ok_bool(bool v) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(v)));
}

static FlMethodResponse* ok_string(const char* s) {
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_string(s ? s : "")));
}

static FlMethodResponse* ok_value(FlValue* v) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(v));
}

static FlMethodResponse* err(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static void emit_event(const char* event_name, int64_t view_id) {
  if (!g_channel) {
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "eventName", fl_value_new_string(event_name));
  fl_value_set_string_take(map, "viewId", fl_value_new_int(view_id));
  fl_method_channel_invoke_method(g_channel, "onEvent", map, nullptr, nullptr,
                                  nullptr);
}

static void emit_view_created(int64_t view_id, int64_t token) {
  if (!g_channel) {
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "eventName", fl_value_new_string("viewCreated"));
  fl_value_set_string_take(map, "viewId", fl_value_new_int(view_id));
  fl_value_set_string_take(map, "token", fl_value_new_int(token));
  fl_method_channel_invoke_method(g_channel, "onEvent", map, nullptr, nullptr,
                                  nullptr);
}

static void maybe_quit_application_if_last_window() {
  if (!g_terminate_after_last_window_closed) {
    return;
  }
  std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
  if (!MvdLinuxWindow::windows.empty()) {
    return;
  }
  GApplication* app = g_application_get_default();
  if (app) {
    g_application_quit(app);
  }
}

static gboolean on_delete(GtkWidget*, GdkEvent*, gpointer data) {
  const int64_t view_id = pointer_to_view_id(data);
  auto wm = MvdLinuxWindow::Find(view_id);
  if (!wm) {
    return FALSE;
  }

  if (!wm->is_pre_confirm) {
    emit_event("preconfirm-close", view_id);
    return TRUE;
  }
  if (wm->is_prevent_close) {
    emit_event("close", view_id);
    return TRUE;
  }
  if (!wm->is_confirm_close) {
    emit_event("confirm-close", view_id);
    return TRUE;
  }

  emit_event("close", view_id);
  MvdLinuxWindow::Unregister(view_id);
  maybe_quit_application_if_last_window();
  return FALSE;
}

static gboolean on_focus_in(GtkWidget*, GdkEvent*, gpointer data) {
  emit_event("focus", pointer_to_view_id(data));
  return FALSE;
}

static gboolean on_focus_out(GtkWidget*, GdkEvent*, gpointer data) {
  emit_event("blur", pointer_to_view_id(data));
  return FALSE;
}

static gboolean on_configure(GtkWidget*, GdkEventConfigure*, gpointer data) {
  emit_event("resize", pointer_to_view_id(data));
  return FALSE;
}

static void connect_window_signals(GtkWindow* window, int64_t view_id) {
  gpointer id_data = view_id_to_pointer(view_id);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete), id_data);
  g_signal_connect(window, "focus-in-event", G_CALLBACK(on_focus_in), id_data);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(on_focus_out), id_data);
  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure), id_data);
}

static void register_window(GtkWindow* window, FlView* view, int64_t view_id) {
  auto wm = std::make_shared<MvdLinuxWindow>();
  wm->view_id = view_id;
  wm->window = window;
  wm->view = view;
  {
    std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
    MvdLinuxWindow::windows[view_id] = wm;
  }
  // FlView quits the app on delete-event; multiview_desktop handles close itself.
  mvd_linux_detach_flutter_quit_on_window_close(window, view);
  connect_window_signals(window, view_id);
}

static FlValue* display_to_map(GdkMonitor* monitor, int index) {
  GdkRectangle geo{};
  GdkRectangle work{};
  gdk_monitor_get_geometry(monitor, &geo);
  gdk_monitor_get_workarea(monitor, &work);

  const double scale = gdk_monitor_get_scale_factor(monitor);

  FlValue* map = fl_value_new_map();
  gchar* id = g_strdup_printf("%d", index);
  fl_value_set_string_take(map, "id", fl_value_new_string(id));
  g_free(id);
  fl_value_set_string_take(map, "name", fl_value_new_string(""));

  FlValue* size = fl_value_new_map();
  fl_value_set_string_take(size, "width",
                           fl_value_new_float(geo.width / scale));
  fl_value_set_string_take(size, "height",
                           fl_value_new_float(geo.height / scale));
  fl_value_set_string_take(map, "size", size);

  FlValue* vis_pos = fl_value_new_map();
  fl_value_set_string_take(vis_pos, "dx",
                           fl_value_new_float(work.x / scale));
  fl_value_set_string_take(vis_pos, "dy",
                           fl_value_new_float(work.y / scale));
  fl_value_set_string_take(map, "visiblePosition", vis_pos);

  FlValue* vis_size = fl_value_new_map();
  fl_value_set_string_take(vis_size, "width",
                           fl_value_new_float(work.width / scale));
  fl_value_set_string_take(vis_size, "height",
                           fl_value_new_float(work.height / scale));
  fl_value_set_string_take(map, "visibleSize", vis_size);

  fl_value_set_string_take(map, "scaleFactor", fl_value_new_float(scale));
  return map;
}

static void handle_screen_method(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  GdkDisplay* display = gdk_display_get_default();

  if (g_strcmp0(method, "getCursorScreenPoint") == 0) {
    GdkSeat* seat = gdk_display_get_default_seat(display);
    GdkDevice* pointer = gdk_seat_get_pointer(seat);
    gint x = 0;
    gint y = 0;
    gdk_device_get_position(pointer, nullptr, &x, &y);
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "dx", fl_value_new_float(x));
    fl_value_set_string_take(map, "dy", fl_value_new_float(y));
    response = ok_value(map);
  } else if (g_strcmp0(method, "getPrimaryDisplay") == 0) {
    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (!monitor) {
      const int n = gdk_display_get_n_monitors(display);
      if (n > 0) {
        monitor = gdk_display_get_monitor(display, 0);
      }
    }
    if (!monitor) {
      response = err("NO_SCREEN", "No primary display found");
    } else {
      response = ok_value(display_to_map(monitor, 0));
    }
  } else if (g_strcmp0(method, "getAllDisplays") == 0) {
    const int n = gdk_display_get_n_monitors(display);
    FlValue* list = fl_value_new_list();
    for (int i = 0; i < n; i++) {
      GdkMonitor* mon = gdk_display_get_monitor(display, i);
      fl_value_append_take(list, display_to_map(mon, i));
    }
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "displays", list);
    response = ok_value(map);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_view_method(FlMethodCall* method_call,
                               const std::shared_ptr<MvdLinuxWindow>& wm) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "closeWindow") == 0) {
    wm->Close();
    response = ok_null();
  } else if (g_strcmp0(method, "isPreventClose") == 0) {
    response = ok_bool(wm->is_prevent_close);
  } else if (g_strcmp0(method, "setPreventClose") == 0) {
    wm->is_prevent_close =
        bool_from_map(args, "isPreventClose", wm->is_prevent_close);
    response = ok_null();
  } else if (g_strcmp0(method, "confirmClose") == 0) {
    wm->is_confirm_close = bool_from_map(args, "confirmClose", true);
    response = ok_null();
  } else if (g_strcmp0(method, "preConfirmClose") == 0) {
    wm->is_pre_confirm = bool_from_map(args, "preConfirmClose", false);
    response = ok_null();
  } else if (g_strcmp0(method, "setTitle") == 0) {
    wm->SetTitle(string_from_map(args, "title"));
    response = ok_null();
  } else if (g_strcmp0(method, "getTitle") == 0) {
    response = ok_string(wm->GetTitle());
  } else if (g_strcmp0(method, "getTitleBarStyle") == 0) {
    response = ok_value(wm->GetTitleBarStyle());
  } else if (g_strcmp0(method, "setTitleBarStyle") == 0) {
    wm->SetTitleBarStyle(
        string_from_map(args, "titleBarStyle"),
        bool_from_map(args, "windowButtonVisibility", true));
    response = ok_null();
  } else if (g_strcmp0(method, "setAsFrameless") == 0) {
    wm->SetAsFrameless();
    response = ok_null();
  } else if (g_strcmp0(method, "show") == 0) {
    wm->Show();
    response = ok_null();
  } else if (g_strcmp0(method, "hide") == 0) {
    wm->Hide();
    response = ok_null();
  } else if (g_strcmp0(method, "isVisible") == 0) {
    response = ok_bool(wm->IsVisible());
  } else if (g_strcmp0(method, "focus") == 0) {
    wm->Focus();
    response = ok_null();
  } else if (g_strcmp0(method, "blur") == 0) {
    response = ok_null();
  } else if (g_strcmp0(method, "isFocused") == 0) {
    response = ok_bool(wm->IsFocused());
  } else if (g_strcmp0(method, "maximize") == 0) {
    wm->Maximize();
    response = ok_null();
  } else if (g_strcmp0(method, "unmaximize") == 0) {
    wm->Unmaximize();
    response = ok_null();
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    response = ok_bool(wm->IsMaximized());
  } else if (g_strcmp0(method, "minimize") == 0) {
    wm->Minimize();
    response = ok_null();
  } else if (g_strcmp0(method, "restore") == 0) {
    wm->Restore();
    response = ok_null();
  } else if (g_strcmp0(method, "isMinimized") == 0) {
    response = ok_bool(wm->IsMinimized());
  } else if (g_strcmp0(method, "isFullScreen") == 0) {
    response = ok_bool(wm->IsFullScreen());
  } else if (g_strcmp0(method, "setFullScreen") == 0) {
    wm->SetFullScreen(bool_from_map(args, "isFullScreen", false));
    response = ok_null();
  } else if (g_strcmp0(method, "getBounds") == 0) {
    response = ok_value(wm->GetBounds());
  } else if (g_strcmp0(method, "setSize") == 0) {
    wm->SetSize(double_from_map(args, "width", 800),
                double_from_map(args, "height", 600));
    response = ok_null();
  } else if (g_strcmp0(method, "setPosition") == 0) {
    FlValue* pos = fl_value_lookup_string(args, "position");
    if (pos && fl_value_get_type(pos) == FL_VALUE_TYPE_MAP) {
      wm->SetPosition(double_from_map(pos, "x", 0), double_from_map(pos, "y", 0));
    }
    response = ok_null();
  } else if (g_strcmp0(method, "center") == 0) {
    wm->Center();
    response = ok_null();
  } else if (g_strcmp0(method, "setMinimumSize") == 0) {
    wm->SetMinimumSize(static_cast<float>(double_from_map(args, "width", -1)),
                       static_cast<float>(double_from_map(args, "height", -1)));
    response = ok_null();
  } else if (g_strcmp0(method, "setMaximumSize") == 0) {
    wm->SetMaximumSize(static_cast<float>(double_from_map(args, "width", -1)),
                       static_cast<float>(double_from_map(args, "height", -1)));
    response = ok_null();
  } else if (g_strcmp0(method, "setAspectRatio") == 0) {
    wm->SetAspectRatio(static_cast<float>(double_from_map(args, "aspectRatio", -1)));
    response = ok_null();
  } else if (g_strcmp0(method, "isResizable") == 0) {
    response = ok_bool(wm->IsResizable());
  } else if (g_strcmp0(method, "setResizable") == 0) {
    wm->SetResizable(bool_from_map(args, "isResizable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isMovable") == 0) {
    response = ok_bool(wm->IsMovable());
  } else if (g_strcmp0(method, "setMovable") == 0) {
    wm->SetMovable(bool_from_map(args, "isMovable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isMinimizable") == 0) {
    response = ok_bool(wm->IsMinimizable());
  } else if (g_strcmp0(method, "setMinimizable") == 0) {
    wm->SetMinimizable(bool_from_map(args, "isMinimizable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isMaximizable") == 0) {
    response = ok_bool(wm->IsMaximizable());
  } else if (g_strcmp0(method, "setMaximizable") == 0) {
    wm->SetMaximizable(bool_from_map(args, "isMaximizable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isClosable") == 0) {
    response = ok_bool(wm->IsClosable());
  } else if (g_strcmp0(method, "setClosable") == 0) {
    wm->SetClosable(bool_from_map(args, "isClosable", true));
    response = ok_null();
  } else if (g_strcmp0(method, "isAlwaysOnTop") == 0) {
    response = ok_bool(false);
  } else if (g_strcmp0(method, "setAlwaysOnTop") == 0) {
    wm->SetAlwaysOnTop(bool_from_map(args, "isAlwaysOnTop", false));
    response = ok_null();
  } else if (g_strcmp0(method, "hideAppFromTaskbar") == 0) {
    wm->SetSkipTaskbar(bool_from_map(args, "isHideAppFromTaskbar", false));
    response = ok_null();
  } else if (g_strcmp0(method, "hasShadow") == 0) {
    response = ok_bool(wm->HasShadow());
  } else if (g_strcmp0(method, "setHasShadow") == 0) {
    wm->SetHasShadow(bool_from_map(args, "hasShadow", true));
    response = ok_null();
  } else if (g_strcmp0(method, "getOpacity") == 0) {
    FlValue* v = fl_value_new_float(wm->GetOpacity());
    response = ok_value(v);
  } else if (g_strcmp0(method, "setOpacity") == 0) {
    wm->SetOpacity(double_from_map(args, "opacity", 1.0));
    response = ok_null();
  } else if (g_strcmp0(method, "setBrightness") == 0) {
    wm->SetBrightness(string_from_map(args, "brightness"));
    response = ok_null();
  } else if (g_strcmp0(method, "setBackgroundColor") == 0) {
    const int r = static_cast<int>(double_from_map(args, "red", 0));
    const int g = static_cast<int>(double_from_map(args, "green", 0));
    const int b = static_cast<int>(double_from_map(args, "blue", 0));
    const int a = static_cast<int>(double_from_map(args, "alpha", 255));
    wm->SetBackgroundColor(r, g, b, a);
    response = ok_null();
  } else if (g_strcmp0(method, "setIgnoreMouseEvents") == 0) {
    wm->SetIgnoreMouseEvents(bool_from_map(args, "ignore", false),
                             bool_from_map(args, "forward", false));
    response = ok_null();
  } else if (g_strcmp0(method, "isIgnoreMouseEvents") == 0) {
    auto [ignore, forward] = wm->IsIgnoreMouseEvents();
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "ignore", fl_value_new_bool(ignore));
    fl_value_set_string_take(map, "forward", fl_value_new_bool(forward));
    response = ok_value(map);
  } else if (g_strcmp0(method, "startDragging") == 0) {
    wm->StartDragging();
    response = ok_null();
  } else if (g_strcmp0(method, "startResizing") == 0) {
    wm->StartResizing(string_from_map(args, "edge"));
    response = ok_null();
  } else if (g_strcmp0(method, "popUpWindowMenu") == 0) {
    wm->PopUpWindowMenu();
    response = ok_null();
  } else if (g_strcmp0(method, "setBadgeLabel") == 0 ||
             g_strcmp0(method, "hideFromCollection") == 0 ||
             g_strcmp0(method, "isHideFromCollection") == 0 ||
             g_strcmp0(method, "isVisibleOnAllWorkspaces") == 0 ||
             g_strcmp0(method, "setVisibleOnAllWorkspaces") == 0) {
    response = ok_null();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void method_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "checkExistViewId") == 0) {
    const int64_t view_id = int64_from_map(args, "viewId");
    response = ok_bool(MvdLinuxWindow::Find(view_id) != nullptr);
  } else if (g_strcmp0(method, "createWindow") == 0) {
    if (!g_create_cb) {
      response = err("createWindow", "WindowCreatedCallback not set in runner");
    } else {
      PendingCreate pending{};
      pending.token = int64_from_map(args, "token");
      pending.width = double_from_map(args, "width", 800);
      pending.height = double_from_map(args, "height", 600);
      pending.title = string_from_map(args, "title");
      pending.title_bar_style = string_from_map(args, "titleBarStyle");
      pending.window_button_visibility =
          bool_from_map(args, "windowButtonVisibility", true);
      FlValue* pos = fl_value_lookup_string(args, "position");
      if (pos && fl_value_get_type(pos) == FL_VALUE_TYPE_MAP) {
        pending.has_position = true;
        pending.pos_x = double_from_map(pos, "x", 0);
        pending.pos_y = double_from_map(pos, "y", 0);
      }
      MvdCreateWindowRequest req{};
      req.token = pending.token;
      req.width = pending.width;
      req.height = pending.height;
      req.title = pending.title.c_str();
      req.title_bar_style = pending.title_bar_style.c_str();
      req.window_button_visibility = pending.window_button_visibility;
      req.has_position = pending.has_position ? TRUE : FALSE;
      req.pos_x = pending.pos_x;
      req.pos_y = pending.pos_y;
      // Call g_create_cb before moving pending; the callback copies strings async.
      g_create_cb(&req);
      {
        std::lock_guard<std::mutex> lk(g_pending_mtx);
        g_pending_create[pending.token] = std::move(pending);
      }
      response = ok_null();
    }
  } else if (g_strcmp0(method, "setTerminateAfterLastWindowClosed") == 0) {
    g_terminate_after_last_window_closed =
        bool_from_map(args, "terminateAfterLastWindowClosed", true);
    response = ok_null();
  } else if (g_strcmp0(method, "setAnchorViewId") == 0) {
    g_anchor_view_id = int64_from_map(args, "viewId");
    response = ok_null();
  } else if (g_strcmp0(method, "isHideAppFromTaskbar") == 0) {
    bool all_hidden = true;
    std::lock_guard<std::mutex> lock(MvdLinuxWindow::registry_mtx);
    for (const auto& p : MvdLinuxWindow::windows) {
      if (!p.second->IsSkipTaskbar()) {
        all_hidden = false;
        break;
      }
    }
    response = ok_bool(all_hidden);
  } else if (g_strcmp0(method, "isHideAppTabFromTaskbar") == 0) {
    const int64_t view_id = int64_from_map(args, "viewId");
    auto wm = MvdLinuxWindow::Find(view_id);
    response = ok_bool(wm && wm->IsSkipTaskbar());
  } else if (g_strcmp0(method, "setProgressBar") == 0) {
    response = ok_null();
  } else {
    const int64_t view_id = int64_from_map(args, "viewId");
    auto wm = MvdLinuxWindow::Find(view_id);
    if (!wm) {
      response = err("NO_WINDOW", "No window for viewId");
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    handle_view_method(method_call, wm);
    return;
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void screen_method_cb(FlMethodChannel*, FlMethodCall* method_call,
                             gpointer) {
  handle_screen_method(method_call);
}

static FlMethodErrorResponse* screen_stream_cancel_cb(FlEventChannel*,
                                                    FlValue*,
                                                    gpointer) {
  g_clear_pointer(&g_screen_event_sink, fl_value_unref);
  return nullptr;
}

static FlMethodErrorResponse* screen_stream_listen_cb(FlEventChannel*,
                                                      FlValue* args,
                                                      gpointer) {
  g_clear_pointer(&g_screen_event_sink, fl_value_unref);
  if (args) {
    g_screen_event_sink = fl_value_ref(args);
  }
  return nullptr;
}

}  // namespace

extern "C" {

void mvd_linux_set_window_created_callback(MvdWindowCreatedCallback callback) {
  g_create_cb = callback;
}

void mvd_linux_register_primary(GtkWindow* window, FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));
  const int64_t view_id = fl_view_get_id(view);
  register_window(window, view, view_id);
  if (g_anchor_view_id < 0) {
    g_anchor_view_id = view_id;
  }
}

void mvd_linux_complete_secondary_window(GtkWindow* window,
                                                       FlView* view,
                                                       int64_t token) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));

  PendingCreate pending{};
  {
    std::lock_guard<std::mutex> lk(g_pending_mtx);
    auto it = g_pending_create.find(token);
    if (it != g_pending_create.end()) {
      pending = std::move(it->second);
      g_pending_create.erase(it);
    }
  }

  const int64_t view_id = fl_view_get_id(view);

  // Center the window when the runner did not receive an explicit position.
  if (!pending.has_position) {
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  }

  register_window(window, view, view_id);

  auto wm = MvdLinuxWindow::Find(view_id);
  if (wm && !pending.title_bar_style.empty()) {
    wm->SetTitleBarStyle(pending.title_bar_style.c_str(),
                         pending.window_button_visibility);
  }

  emit_view_created(view_id, token);
}

void mvd_linux_detach_flutter_quit_on_window_close(
    GtkWindow* window,
    FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));
  const guint signal_id = g_signal_lookup("delete-event", GTK_TYPE_WIDGET);
  if (signal_id == 0) {
    return;
  }
  g_signal_handlers_disconnect_matched(
      G_OBJECT(window),
      static_cast<GSignalMatchType>(G_SIGNAL_MATCH_ID | G_SIGNAL_MATCH_DATA),
      signal_id, static_cast<GQuark>(0), nullptr, nullptr, view);
}

void multiview_desktop_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* ch = fl_method_channel_new(
      messenger, "multiview_desktop", FL_METHOD_CODEC(codec));
  if (g_channel) {
    g_object_unref(g_channel);
  }
  g_channel = ch;
  fl_method_channel_set_method_call_handler(g_channel, method_cb, nullptr,
                                            nullptr);

  FlMethodChannel* screen_ch = fl_method_channel_new(
      messenger, "multiview_desktop/screen_retriever", FL_METHOD_CODEC(codec));
  if (g_screen_channel) {
    g_object_unref(g_screen_channel);
  }
  g_screen_channel = screen_ch;
  fl_method_channel_set_method_call_handler(g_screen_channel, screen_method_cb,
                                            nullptr, nullptr);

  g_autoptr(FlStandardMethodCodec) event_codec = fl_standard_method_codec_new();
  FlEventChannel* event_ch = fl_event_channel_new(
      messenger, "multiview_desktop/screen_retriever_event",
      FL_METHOD_CODEC(event_codec));
  if (g_screen_event_channel) {
    g_object_unref(g_screen_event_channel);
  }
  g_screen_event_channel = event_ch;
  fl_event_channel_set_stream_handlers(
      g_screen_event_channel, screen_stream_listen_cb, screen_stream_cancel_cb,
      nullptr, nullptr);
}

}  // extern "C"
