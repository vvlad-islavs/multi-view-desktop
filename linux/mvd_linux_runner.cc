#include <multiview_desktop/multiview_desktop_runner.h>

#include "mvd_linux_internal.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <gtk/gtk.h>

#include <memory>
#include <string>

namespace {

FlEngine* g_shared_engine = nullptr;
GtkApplication* g_app = nullptr;
const char* g_default_title = "Flutter";

static void first_frame_cb(gpointer user_data, FlView* view) {
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GPOINTER_TO_INT(user_data)) {
    gtk_widget_show(top);
  }
}

static gchar* resolve_flutter_bundle_root(void) {
  g_autofree gchar* self = g_file_read_link("/proc/self/exe", nullptr);
  if (!self) {
    return nullptr;
  }
  g_autofree gchar* exe_dir = g_path_get_dirname(self);
  {
    g_autofree gchar* test =
        g_build_filename(exe_dir, "data", "flutter_assets", nullptr);
    if (g_file_test(test, G_FILE_TEST_IS_DIR)) {
      return g_strdup(exe_dir);
    }
  }
  {
    g_autofree gchar* peer =
        g_build_filename(exe_dir, "..", "bundle", nullptr);
    g_autofree gchar* canon = g_canonicalize_filename(peer, nullptr);
    if (!canon) {
      return nullptr;
    }
    g_autofree gchar* test =
        g_build_filename(canon, "data", "flutter_assets", nullptr);
    if (g_file_test(test, G_FILE_TEST_IS_DIR)) {
      return g_strdup(canon);
    }
  }
  return nullptr;
}

static void decorate_toplevel_window(GtkWindow* window, const char* title) {
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, title);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, title);
  }
}

static void create_secondary_window(const MvdCreateWindowRequest* request) {
  if (!g_app || !g_shared_engine || !request) {
    return;
  }

  const char* title =
      (request->title && request->title[0]) ? request->title : g_default_title;

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(g_app)));
  decorate_toplevel_window(window, title);
  gtk_window_set_default_size(window, static_cast<int>(request->width),
                              static_cast<int>(request->height));
  if (request->has_position) {
    gtk_window_move(window, static_cast<int>(request->pos_x),
                    static_cast<int>(request->pos_y));
  }

  FlView* view = fl_view_new_for_engine(g_shared_engine);

  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           GINT_TO_POINTER(0));
  gtk_widget_realize(GTK_WIDGET(view));

  mvd_linux_complete_secondary_window(window, view, request->token);

  gtk_widget_show(GTK_WIDGET(window));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static void window_created_callback(const MvdCreateWindowRequest* request) {
  struct Ctx {
    MvdCreateWindowRequest request;
  };
  auto* ctx = new Ctx{*request};
  g_main_context_invoke(
      nullptr,
      [](gpointer data) -> gboolean {
        std::unique_ptr<Ctx> c(static_cast<Ctx*>(data));
        create_secondary_window(&c->request);
        return G_SOURCE_REMOVE;
      },
      ctx);
}

}  // namespace

extern "C" {

void multiview_desktop_linux_runner_install(GtkApplication* application) {
  g_app = application;
  mvd_linux_set_window_created_callback(window_created_callback);
}

void multiview_desktop_linux_runner_prepare_dart_project(FlDartProject* project) {
  g_return_if_fail(FL_IS_DART_PROJECT(project));
  g_autofree gchar* root = resolve_flutter_bundle_root();
  if (!root) {
    return;
  }
  g_autofree gchar* assets =
      g_build_filename(root, "data", "flutter_assets", nullptr);
  g_autofree gchar* icu =
      g_build_filename(root, "data", "icudtl.dat", nullptr);
  fl_dart_project_set_assets_path(project, g_strdup(assets));
  fl_dart_project_set_icu_data_path(project, g_strdup(icu));
  g_autofree gchar* aot = g_build_filename(root, "lib", "libapp.so", nullptr);
  if (g_file_test(aot, G_FILE_TEST_IS_REGULAR)) {
    fl_dart_project_set_aot_library_path(project, g_strdup(aot));
  } else {
    fl_dart_project_set_aot_library_path(project, nullptr);
  }
}

void multiview_desktop_linux_runner_register_primary(GtkWindow* window,
                                                     FlView* view) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(FL_IS_VIEW(view));
  g_shared_engine = fl_view_get_engine(view);
  mvd_linux_register_primary(window, view);
}

void multiview_desktop_linux_runner_set_default_title(const char* title) {
  if (title && title[0]) {
    g_default_title = title;
  }
}

}  // extern "C"
