#ifndef MVD_LINUX_WINDOW_H_
#define MVD_LINUX_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>

class MvdLinuxWindow {
 public:
  MvdLinuxWindow();
  ~MvdLinuxWindow();

  static std::mutex registry_mtx;
  static std::map<int64_t, std::shared_ptr<MvdLinuxWindow>> windows;

  int64_t view_id = -1;
  GtkWindow* window = nullptr;
  FlView* view = nullptr;

  bool is_prevent_close = false;
  bool is_confirm_close = false;
  bool is_pre_confirm = false;
  bool is_minimizable = true;
  bool is_resizable = true;
  bool is_skip_taskbar = false;
  bool window_button_visibility = true;
  bool is_ignore_mouse_events = false;
  bool is_forward_mouse_events = false;
  double opacity = 1.0;

  GdkGeometry geometry{};
  GdkWindowHints hints = static_cast<GdkWindowHints>(0);
  GtkCssProvider* css_provider = nullptr;
  gchar* title_bar_style = nullptr;
  GdkEventButton last_button{};

  void SetAsFrameless();
  void Close();
  void Focus();
  bool IsFocused();
  void Show();
  void Hide();
  bool IsVisible();
  bool IsMaximized();
  void Maximize();
  void Unmaximize();
  bool IsMinimized();
  void Minimize();
  void Restore();
  bool IsFullScreen();
  void SetFullScreen(bool fs);
  void SetAspectRatio(float ar);
  bool SetBackgroundColor(int r, int g, int b, int a);
  FlValue* GetBounds();
  void SetBounds(FlValue* args);
  void SetSize(double width, double height);
  void SetPosition(double x, double y);
  void Center();
  void SetMinimumSize(float w, float h);
  void SetMaximumSize(float w, float h);
  void ReapplyGeometryHints();
  bool IsResizable();
  void SetResizable(bool v);
  bool IsMinimizable();
  void SetMinimizable(bool v);
  bool IsMaximizable();
  void SetMaximizable(bool v);
  bool IsClosable();
  void SetClosable(bool v);
  void SetAlwaysOnTop(bool v);
  const gchar* GetTitle();
  void SetTitle(const gchar* t);
  void SetTitleBarStyle(const gchar* style, bool window_button_visibility);
  FlValue* GetTitleBarStyle();
  bool IsSkipTaskbar();
  void SetSkipTaskbar(bool v);
  double GetOpacity();
  void SetOpacity(double o);
  void SetBrightness(const gchar* brightness);
  void PopUpWindowMenu();
  void StartDragging();
  void StartResizing(const gchar* edge);
  bool IsMovable();
  void SetMovable(bool v);
  bool HasShadow();
  void SetHasShadow(bool v);
  void SetIgnoreMouseEvents(bool ignore, bool forward);
  std::pair<bool, bool> IsIgnoreMouseEvents();

  void ApplyWindowTypeHint();

  static std::shared_ptr<MvdLinuxWindow> Find(int64_t view_id);
  static void Unregister(int64_t view_id);
  static GdkWindow* GetGdkWindow(GtkWindow* w);
  static GtkWidget* HeaderBarOf(GtkWindow* w);
  static FlValue* MakeBounds(GtkWindow* w);
};

#endif  // MVD_LINUX_WINDOW_H_
