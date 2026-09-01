#ifndef MVD_LINUX_INTERNAL_H_
#define MVD_LINUX_INTERNAL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <glib.h>
#include <stdint.h>

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

typedef int64_t (*MvdWindowCreatedCallback)(const MvdCreateWindowRequest* request);

void mvd_linux_set_window_created_callback(MvdWindowCreatedCallback callback);

void mvd_linux_register_primary(GtkWindow* window, FlView* view);

int64_t mvd_linux_complete_secondary_window(GtkWindow* window,
                                            FlView* view,
                                            int64_t token);

void mvd_linux_detach_flutter_quit_on_window_close(GtkWindow* window,
                                                   FlView* view);

int64_t mvd_linux_queue_create_window(int64_t token,
                                      double width,
                                      double height,
                                      const char* title,
                                      const char* title_bar_style,
                                      int window_button_visibility,
                                      int has_position,
                                      double pos_x,
                                      double pos_y);

int64_t mvd_linux_queue_create_dialog(int64_t token,
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

int64_t mvd_linux_queue_create_popup(int64_t token,
                                     int64_t parent_id,
                                     int width,
                                     int height);

void mvd_linux_set_anchor_view_id(int64_t view_id);

void mvd_linux_set_terminate_after_last(int terminate);

void mvd_linux_complete_modal_dialog(int64_t view_id);

typedef void (*MvdEventCallback)(const char* event_name, int64_t view_id,
                                 int64_t arg);

void mvd_set_event_callback(MvdEventCallback cb);

int64_t mvd_event_callback_generation(void);

void mvd_detach_isolate_callbacks(void* token);

void mvd_linux_clear_screen_event_callback(void);

int32_t mvd_emit_event(const char* event_name, int64_t view_id, int64_t arg);

#ifdef __cplusplus
}
#endif

#endif  // MVD_LINUX_INTERNAL_H_
