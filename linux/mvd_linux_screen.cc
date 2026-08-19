#include "mvd_linux_screen.h"

#include <multiview_desktop/multiview_desktop_plugin.h>

#include <gdk/gdk.h>
#include <glib.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <string>

namespace {

constexpr int kStrCap = 8192;

double g_screen_rect[4] = {0, 0, 0, 0};
char g_screen_str[kStrCap] = {};

FlMethodChannel* g_screen_channel = nullptr;
FlEventChannel* g_screen_event_channel = nullptr;
bool g_screen_listening = false;
gulong g_monitor_added_id = 0;
gulong g_monitor_removed_id = 0;

typedef void (*MvdScreenEventCallback)(const char* type);
MvdScreenEventCallback g_screen_event_cb = nullptr;

std::string json_escape(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (const unsigned char c : s) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      default:
        out += static_cast<char>(c);
        break;
    }
  }
  return out;
}

struct DisplayBits {
  std::string id;
  std::string name;
  double w = 0;
  double h = 0;
  double vx = 0;
  double vy = 0;
  double vw = 0;
  double vh = 0;
  double scale = 1;
};

DisplayBits bits_from_monitor(GdkMonitor* monitor, int index) {
  DisplayBits bits;
  GdkRectangle geo{};
  GdkRectangle work{};
  gdk_monitor_get_geometry(monitor, &geo);
  gdk_monitor_get_workarea(monitor, &work);

  // On X11, GDK returns physical pixel coordinates from gdk_monitor_get_geometry
  // and gdk_monitor_get_workarea. gdk_device_get_position also returns physical
  // pixels. All GTK window operations also use physical X11 coordinates.
  // Dividing by gdk_monitor_get_scale_factor would mismatch that system.
  bits.scale = gdk_monitor_get_scale_factor(monitor);
  const char* model = gdk_monitor_get_model(monitor);
  bits.id = std::to_string(index);
  bits.name = model ? model : "";
  bits.w = geo.width;
  bits.h = geo.height;
  bits.vx = work.x;
  bits.vy = work.y;
  bits.vw = work.width;
  bits.vh = work.height;
  return bits;
}

std::string display_bits_to_json(const DisplayBits& bits) {
  std::ostringstream o;
  o << "{\"id\":\"" << json_escape(bits.id) << "\",\"name\":\""
    << json_escape(bits.name) << "\",\"size\":{\"width\":" << bits.w
    << ",\"height\":" << bits.h << "},\"visiblePosition\":{\"dx\":" << bits.vx
    << ",\"dy\":" << bits.vy << "},\"visibleSize\":{\"width\":" << bits.vw
    << ",\"height\":" << bits.vh << "},\"scaleFactor\":" << bits.scale << "}";
  return o.str();
}

FlValue* display_to_map(GdkMonitor* monitor, int index) {
  const DisplayBits bits = bits_from_monitor(monitor, index);
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "id", fl_value_new_string(bits.id.c_str()));
  fl_value_set_string_take(map, "name", fl_value_new_string(bits.name.c_str()));

  FlValue* size = fl_value_new_map();
  fl_value_set_string_take(size, "width", fl_value_new_float(bits.w));
  fl_value_set_string_take(size, "height", fl_value_new_float(bits.h));
  fl_value_set_string_take(map, "size", size);

  FlValue* vis_pos = fl_value_new_map();
  fl_value_set_string_take(vis_pos, "dx", fl_value_new_float(bits.vx));
  fl_value_set_string_take(vis_pos, "dy", fl_value_new_float(bits.vy));
  fl_value_set_string_take(map, "visiblePosition", vis_pos);

  FlValue* vis_size = fl_value_new_map();
  fl_value_set_string_take(vis_size, "width", fl_value_new_float(bits.vw));
  fl_value_set_string_take(vis_size, "height", fl_value_new_float(bits.vh));
  fl_value_set_string_take(map, "visibleSize", vis_size);

  fl_value_set_string_take(map, "scaleFactor", fl_value_new_float(bits.scale));
  return map;
}

GdkMonitor* primary_monitor(GdkDisplay* display, int* index) {
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  int i = 0;
  if (!monitor) {
    const int n = gdk_display_get_n_monitors(display);
    if (n > 0) {
      monitor = gdk_display_get_monitor(display, 0);
    }
  } else {
    const int n = gdk_display_get_n_monitors(display);
    for (int k = 0; k < n; k++) {
      if (gdk_display_get_monitor(display, k) == monitor) {
        i = k;
        break;
      }
    }
  }
  if (index) {
    *index = i;
  }
  return monitor;
}

int write_cstr(char* buf, int cap, const std::string& s) {
  if (!buf || cap <= 0 || s.empty()) {
    return 0;
  }
  const int n = std::min(cap - 1, static_cast<int>(s.size()));
  std::memcpy(buf, s.c_str(), static_cast<size_t>(n));
  buf[n] = 0;
  return 1;
}

int linux_cursor(double* x, double* y) {
  GdkDisplay* display = gdk_display_get_default();
  if (!display || !x || !y) {
    return 0;
  }
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = seat ? gdk_seat_get_pointer(seat) : nullptr;
  if (!pointer) {
    return 0;
  }
  gint px = 0;
  gint py = 0;
  gdk_device_get_position(pointer, nullptr, &px, &py);
  *x = px;
  *y = py;
  return 1;
}

int linux_primary_json(char* buf, int cap) {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) {
    return 0;
  }
  int index = 0;
  GdkMonitor* monitor = primary_monitor(display, &index);
  if (!monitor) {
    return 0;
  }
  return write_cstr(buf, cap, display_bits_to_json(bits_from_monitor(monitor, index)));
}

int linux_all_json(char* buf, int cap) {
  GdkDisplay* display = gdk_display_get_default();
  if (!display) {
    return 0;
  }
  const int n = gdk_display_get_n_monitors(display);
  if (n <= 0) {
    return 0;
  }
  std::ostringstream o;
  o << "[";
  for (int i = 0; i < n; i++) {
    if (i > 0) {
      o << ",";
    }
    GdkMonitor* mon = gdk_display_get_monitor(display, i);
    o << display_bits_to_json(bits_from_monitor(mon, i));
  }
  o << "]";
  return write_cstr(buf, cap, o.str());
}

FlMethodResponse* ok_value(FlValue* v) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(v));
}

FlMethodResponse* err(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

void emit_screen_event(const char* type) {
  if (g_screen_event_cb) {
    g_screen_event_cb(type);
  }
  if (g_screen_listening && g_screen_event_channel) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "type", fl_value_new_string(type));
    fl_event_channel_send(g_screen_event_channel, map, nullptr, nullptr);
  }
}

void on_monitor_added(GdkDisplay*, GdkMonitor*, gpointer) {
  emit_screen_event("display-added");
}

void on_monitor_removed(GdkDisplay*, GdkMonitor*, gpointer) {
  emit_screen_event("display-removed");
}

void handle_screen_method(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  GdkDisplay* display = gdk_display_get_default();

  if (g_strcmp0(method, "getCursorScreenPoint") == 0) {
    double x = 0;
    double y = 0;
    linux_cursor(&x, &y);
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "dx", fl_value_new_float(x));
    fl_value_set_string_take(map, "dy", fl_value_new_float(y));
    response = ok_value(map);
  } else if (g_strcmp0(method, "getPrimaryDisplay") == 0) {
    int index = 0;
    GdkMonitor* monitor = primary_monitor(display, &index);
    if (!monitor) {
      response = err("NO_SCREEN", "No primary display found");
    } else {
      response = ok_value(display_to_map(monitor, index));
    }
  } else if (g_strcmp0(method, "getAllDisplays") == 0) {
    const int n = display ? gdk_display_get_n_monitors(display) : 0;
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

void screen_method_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer) {
  handle_screen_method(method_call);
}

FlMethodErrorResponse* screen_stream_cancel_cb(FlEventChannel*, FlValue*,
                                               gpointer) {
  g_screen_listening = false;
  return nullptr;
}

FlMethodErrorResponse* screen_stream_listen_cb(FlEventChannel*, FlValue*,
                                               gpointer) {
  g_screen_listening = true;
  return nullptr;
}

void connect_monitor_signals() {
  GdkDisplay* display = gdk_display_get_default();
  if (!display || g_monitor_added_id != 0) {
    return;
  }
  g_monitor_added_id = g_signal_connect(display, "monitor-added",
                                        G_CALLBACK(on_monitor_added), nullptr);
  g_monitor_removed_id = g_signal_connect(
      display, "monitor-removed", G_CALLBACK(on_monitor_removed), nullptr);
}

}  // namespace

extern "C" {

void mvd_linux_screen_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
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

  connect_monitor_signals();
}

FLUTTER_PLUGIN_EXPORT double* mvd_screen_rect_buf_ptr() { return g_screen_rect; }

FLUTTER_PLUGIN_EXPORT char* mvd_screen_str_buf_ptr() { return g_screen_str; }

FLUTTER_PLUGIN_EXPORT void mvd_set_screen_event_callback(
    void (*cb)(const char*)) {
  g_screen_event_cb = cb;
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_cursor_screen_point(double) {
  double x = 0;
  double y = 0;
  if (!linux_cursor(&x, &y)) {
    return 0;
  }
  g_screen_rect[0] = x;
  g_screen_rect[1] = y;
  return 1;
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_primary_display() {
  return linux_primary_json(g_screen_str, kStrCap);
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_all_displays() {
  return linux_all_json(g_screen_str, kStrCap);
}

}  // extern "C"
