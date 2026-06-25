#include "flutter_window.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr char kClipboardEventChannel[] = "clipsync/clipboard_events";
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupClipboardEventChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupClipboardEventChannel() {
  clipboard_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kClipboardEventChannel,
      &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        clipboard_sink_ = std::move(events);
        if (GetHandle() != nullptr) {
          AddClipboardFormatListener(GetHandle());
        }
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        if (GetHandle() != nullptr) {
          RemoveClipboardFormatListener(GetHandle());
        }
        clipboard_sink_.reset();
        return nullptr;
      });

  clipboard_channel_->SetStreamHandler(std::move(handler));
}

void FlutterWindow::NotifyClipboardChanged() {
  if (clipboard_sink_) {
    clipboard_sink_->Success(flutter::EncodableValue());
  }
}

void FlutterWindow::OnDestroy() {
  if (GetHandle() != nullptr) {
    RemoveClipboardFormatListener(GetHandle());
  }
  clipboard_sink_.reset();
  if (clipboard_channel_) {
    clipboard_channel_->SetStreamHandler(nullptr);
    clipboard_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_CLIPBOARDUPDATE:
      NotifyClipboardChanged();
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
