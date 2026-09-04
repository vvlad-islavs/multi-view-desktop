#ifndef MVD_WINDOWS_SCREEN_H_
#define MVD_WINDOWS_SCREEN_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <windows.h>

namespace multi_view_desktop {

UINT MvdWindowsDpiForMonitor(HMONITOR monitor);
double MvdWindowsScaleForMonitor(HMONITOR monitor);
double MvdWindowsScaleForHwnd(HWND hwnd);
double MvdWindowsScaleForLogicalRect(double x, double y, double w, double h);
void MvdWindowsPhysicalSizeMm(HMONITOR monitor, double* width_mm,
                              double* height_mm);

void MvdWindowsRegisterScreenRetriever(
    flutter::BinaryMessenger* messenger,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>*
        out_channel);

void MvdWindowsNotifyDisplayChange();

void MvdWindowsClearScreenEventCallback();

}  // namespace multi_view_desktop

#endif  // MVD_WINDOWS_SCREEN_H_
