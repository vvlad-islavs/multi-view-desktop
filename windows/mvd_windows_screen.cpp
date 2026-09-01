#include "mvd_windows_screen.h"

#include "include/multi_view_desktop/multi_view_desktop.h"

#include <windows.h>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr int kStrCap = 8192;

double g_screen_rect[4] = {0, 0, 0, 0};
char g_screen_str[kStrCap] = {};
int g_monitor_count = -1;
void (*g_screen_event_cb)(const char*) = nullptr;

struct MwmMonitorData {
  RECT geometry{};
  RECT workarea{};
  HMONITOR handle = nullptr;
  int index = 0;
};

BOOL CALLBACK MwmEnumMonitorsProc(HMONITOR monitor, HDC, LPRECT, LPARAM lparam) {
  auto* list = reinterpret_cast<std::vector<MwmMonitorData>*>(lparam);
  MONITORINFO info;
  info.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfo(monitor, &info)) {
    MwmMonitorData data;
    data.handle = monitor;
    data.geometry = info.rcMonitor;
    data.workarea = info.rcWork;
    data.index = static_cast<int>(list->size());
    list->push_back(data);
  }
  return TRUE;
}

UINT MwmGetDpiForMonitor(HMONITOR monitor) {
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

std::string MwmWcharToUtf8(const wchar_t* wstr) {
  const int len =
      WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0) {
    return {};
  }
  std::string buf(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf.data(), len, nullptr, nullptr);
  return buf;
}

std::string JsonEscape(const std::string& s) {
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
  double vis_x = 0;
  double vis_y = 0;
  double vis_w = 0;
  double vis_h = 0;
  double scale = 1;
};

DisplayBits MonitorBits(const MwmMonitorData& data) {
  DisplayBits bits;
  constexpr double k_base_dpi = 96.0;
  bits.scale = MwmGetDpiForMonitor(data.handle) / k_base_dpi;
  bits.vis_x = std::round(data.workarea.left / bits.scale);
  bits.vis_y = std::round(data.workarea.top / bits.scale);
  bits.vis_w =
      std::round((data.workarea.right - data.workarea.left) / bits.scale);
  bits.vis_h =
      std::round((data.workarea.bottom - data.workarea.top) / bits.scale);
  bits.w = std::round(data.geometry.right / bits.scale - bits.vis_x);
  bits.h = std::round(data.geometry.bottom / bits.scale - bits.vis_y);

  MONITORINFOEX info_ex;
  info_ex.cbSize = sizeof(MONITORINFOEX);
  if (GetMonitorInfo(data.handle, &info_ex)) {
    bits.name = MwmWcharToUtf8(info_ex.szDevice);
    DISPLAY_DEVICE display_device;
    display_device.cb = sizeof(DISPLAY_DEVICE);
    int idx = 0;
    while (EnumDisplayDevices(info_ex.szDevice, idx, &display_device, 0)) {
      if ((display_device.StateFlags & DISPLAY_DEVICE_ACTIVE) &&
          (display_device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) {
        const std::wstring dev_name(display_device.DeviceName);
        if (dev_name.find(info_ex.szDevice) == 0) {
          bits.id = MwmWcharToUtf8(display_device.DeviceID);
          break;
        }
      }
      ++idx;
    }
  }
  return bits;
}

std::string DisplayBitsToJson(const DisplayBits& bits) {
  std::ostringstream o;
  o << "{\"id\":\"" << JsonEscape(bits.id) << "\",\"name\":\""
    << JsonEscape(bits.name) << "\",\"size\":{\"width\":" << bits.w
    << ",\"height\":" << bits.h << "},\"visiblePosition\":{\"dx\":" << bits.vis_x
    << ",\"dy\":" << bits.vis_y << "},\"visibleSize\":{\"width\":" << bits.vis_w
    << ",\"height\":" << bits.vis_h << "},\"scaleFactor\":" << bits.scale
    << "}";
  return o.str();
}

flutter::EncodableMap MonitorToMap(const MwmMonitorData& data) {
  const DisplayBits bits = MonitorBits(data);
  return flutter::EncodableMap{
      {flutter::EncodableValue("id"), flutter::EncodableValue(bits.id)},
      {flutter::EncodableValue("name"), flutter::EncodableValue(bits.name)},
      {flutter::EncodableValue("size"),
       flutter::EncodableValue(flutter::EncodableMap{
           {flutter::EncodableValue("width"), flutter::EncodableValue(bits.w)},
           {flutter::EncodableValue("height"), flutter::EncodableValue(bits.h)},
       })},
      {flutter::EncodableValue("visiblePosition"),
       flutter::EncodableValue(flutter::EncodableMap{
           {flutter::EncodableValue("dx"), flutter::EncodableValue(bits.vis_x)},
           {flutter::EncodableValue("dy"), flutter::EncodableValue(bits.vis_y)},
       })},
      {flutter::EncodableValue("visibleSize"),
       flutter::EncodableValue(flutter::EncodableMap{
           {flutter::EncodableValue("width"),
            flutter::EncodableValue(bits.vis_w)},
           {flutter::EncodableValue("height"),
            flutter::EncodableValue(bits.vis_h)},
       })},
      {flutter::EncodableValue("scaleFactor"),
       flutter::EncodableValue(bits.scale)},
  };
}

void CursorPoint(double device_pixel_ratio, double* x, double* y) {
  POINT point;
  GetCursorPos(&point);
  const double dpr = device_pixel_ratio > 0 ? device_pixel_ratio : 1.0;
  *x = point.x / dpr;
  *y = point.y / dpr;
}

std::string PrimaryDisplayJson() {
  const HMONITOR primary =
      MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info;
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(primary, &info)) {
    return {};
  }
  MwmMonitorData data;
  data.handle = primary;
  data.geometry = info.rcMonitor;
  data.workarea = info.rcWork;
  return DisplayBitsToJson(MonitorBits(data));
}

std::string AllDisplaysJson() {
  std::vector<MwmMonitorData> monitors;
  EnumDisplayMonitors(nullptr, nullptr, MwmEnumMonitorsProc,
                      reinterpret_cast<LPARAM>(&monitors));
  std::ostringstream o;
  o << "[";
  for (size_t i = 0; i < monitors.size(); ++i) {
    if (i > 0) {
      o << ",";
    }
    o << DisplayBitsToJson(MonitorBits(monitors[i]));
  }
  o << "]";
  return o.str();
}

int32_t CopyJson(const std::string& json) {
  if (json.empty()) {
    g_screen_str[0] = 0;
    return 0;
  }
  std::strncpy(g_screen_str, json.c_str(), kStrCap - 1);
  g_screen_str[kStrCap - 1] = 0;
  return 1;
}

void HandleScreenCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  double device_pixel_ratio = 1.0;
  if (method_call.arguments() && !method_call.arguments()->IsNull()) {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(method_call.arguments())) {
      const auto it = args->find(flutter::EncodableValue("devicePixelRatio"));
      if (it != args->end()) {
        if (const auto* value = std::get_if<double>(&it->second)) {
          device_pixel_ratio = *value;
        }
      }
    }
  }

  if (method == "getCursorScreenPoint") {
    double x = 0;
    double y = 0;
    CursorPoint(device_pixel_ratio, &x, &y);
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("dx"), flutter::EncodableValue(x)},
        {flutter::EncodableValue("dy"), flutter::EncodableValue(y)},
    }));
  } else if (method == "getPrimaryDisplay") {
    const HMONITOR primary =
        MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info;
    info.cbSize = sizeof(MONITORINFO);
    if (GetMonitorInfo(primary, &info)) {
      MwmMonitorData data;
      data.handle = primary;
      data.geometry = info.rcMonitor;
      data.workarea = info.rcWork;
      result->Success(flutter::EncodableValue(MonitorToMap(data)));
    } else {
      result->Error("NO_MONITOR", "No monitors found");
    }
  } else if (method == "getAllDisplays") {
    std::vector<MwmMonitorData> monitors;
    EnumDisplayMonitors(nullptr, nullptr, MwmEnumMonitorsProc,
                        reinterpret_cast<LPARAM>(&monitors));
    flutter::EncodableList list;
    for (const auto& monitor : monitors) {
      list.push_back(flutter::EncodableValue(MonitorToMap(monitor)));
    }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("displays"), flutter::EncodableValue(list)},
    }));
  } else {
    result->NotImplemented();
  }
}

}  // namespace

namespace multi_view_desktop {

void MvdWindowsRegisterScreenRetriever(
    flutter::BinaryMessenger* messenger,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>*
        out_channel) {
  auto screen_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "multiview_desktop/screen_retriever",
          &flutter::StandardMethodCodec::GetInstance());
  screen_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleScreenCall(call, std::move(result));
      });
  *out_channel = std::move(screen_channel);
  std::vector<MwmMonitorData> monitors;
  EnumDisplayMonitors(nullptr, nullptr, MwmEnumMonitorsProc,
                      reinterpret_cast<LPARAM>(&monitors));
  g_monitor_count = static_cast<int>(monitors.size());
}

void MvdWindowsNotifyDisplayChange() {
  std::vector<MwmMonitorData> monitors;
  EnumDisplayMonitors(nullptr, nullptr, MwmEnumMonitorsProc,
                      reinterpret_cast<LPARAM>(&monitors));
  const int count = static_cast<int>(monitors.size());
  if (g_monitor_count < 0) {
    g_monitor_count = count;
    return;
  }
  if (count != g_monitor_count && g_screen_event_cb) {
    g_screen_event_cb(count > g_monitor_count ? "display-added"
                                             : "display-removed");
  }
  g_monitor_count = count;
}

void MvdWindowsClearScreenEventCallback() { g_screen_event_cb = nullptr; }

}  // namespace multi_view_desktop

extern "C" {

FLUTTER_PLUGIN_EXPORT double* mvd_screen_rect_buf_ptr() { return g_screen_rect; }

FLUTTER_PLUGIN_EXPORT char* mvd_screen_str_buf_ptr() { return g_screen_str; }

FLUTTER_PLUGIN_EXPORT void mvd_set_screen_event_callback(
    void (*cb)(const char*)) {
  g_screen_event_cb = cb;
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_cursor_screen_point(
    double device_pixel_ratio) {
  double x = 0;
  double y = 0;
  CursorPoint(device_pixel_ratio, &x, &y);
  g_screen_rect[0] = x;
  g_screen_rect[1] = y;
  return 1;
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_primary_display() {
  return CopyJson(PrimaryDisplayJson());
}

FLUTTER_PLUGIN_EXPORT int32_t mvd_get_all_displays() {
  return CopyJson(AllDisplaysJson());
}

}  // extern "C"
