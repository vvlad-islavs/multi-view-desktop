#ifndef MVD_LINUX_INTERNAL_H_
#define MVD_LINUX_INTERNAL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <glib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  int64_t token;
  double width;
  double height;
  const char* title;
  const char* title_bar_style;
  gboolean window_button_visibility;
  gboolean has_position;
  double pos_x;
  double pos_y;
} MvdCreateWindowRequest;

typedef void (*MvdWindowCreatedCallback)(const MvdCreateWindowRequest* request);

void mvd_linux_set_window_created_callback(MvdWindowCreatedCallback callback);

void mvd_linux_register_primary(GtkWindow* window, FlView* view);

void mvd_linux_complete_secondary_window(GtkWindow* window,
                                         FlView* view,
                                         int64_t token);

void mvd_linux_detach_flutter_quit_on_window_close(GtkWindow* window,
                                                   FlView* view);

void mvd_linux_queue_create_window(int64_t token,
                                   double width,
                                   double height,
                                   const char* title,
                                   const char* title_bar_style,
                                   int window_button_visibility,
                                   int has_position,
                                   double pos_x,
                                   double pos_y);

void mvd_linux_queue_create_dialog(int64_t token,
                                   int64_t parent_id,
                                   int width,
                                   int height,
                                   int is_modal,
                                   const char* title,
                                   const char* title_bar_style,
                                   int window_button_visibility,
                                   int has_position,
                                   int pos_x,
                                   int pos_y);

void mvd_linux_queue_create_popup(int64_t token,
                                  int64_t parent_id,
                                  int width,
                                  int height);

void mvd_linux_set_anchor_view_id(int64_t view_id);

void mvd_linux_set_terminate_after_last(int terminate);

#ifdef __cplusplus
}
#endif

#endif  // MVD_LINUX_INTERNAL_H_
