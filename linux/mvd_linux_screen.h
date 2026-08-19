#ifndef MVD_LINUX_SCREEN_H_
#define MVD_LINUX_SCREEN_H_

#include <flutter_linux/flutter_linux.h>

#ifdef __cplusplus
extern "C" {
#endif

void mvd_linux_screen_register(FlBinaryMessenger* messenger);

#ifdef __cplusplus
}
#endif

#endif  // MVD_LINUX_SCREEN_H_
