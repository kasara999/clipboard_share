[日本語版はこちら](README.ja.md)

# ClipSync — Clipboard Sharing Between Windows and iPhone

Real-time clipboard sync between Windows and iPhone, supporting both text and images.

## Background

I built this app out of personal frustration: whenever I copied a URL or image on my iPhone and needed it on my Windows PC, I had to route it through LINE's Keep Memo as a makeshift relay. That friction was enough to motivate building a proper solution — an app that shares the clipboard directly between devices over the local network.

## Features

- Copy on Windows, paste on iPhone — and vice versa
- Supports both text and image clipboard content
- Clipboard history up to 50 entries
- One-tap pairing via QR code
- Token-based authentication to block unauthorized connections on the same Wi-Fi

## Requirements

- **Windows**: Windows 10 or later
- **iPhone**: iOS 16 or later — iOS app is in a separate repository: [clipboard_share_ios](https://github.com/kasara999/clipboard_share_ios)
- **Network**: Both devices must be on the same Wi-Fi network

## Installation

**Windows:** Download `ClipSync-Setup.exe` from the [latest release](https://github.com/kasara999/clipboard_share/releases/latest) and run it.

**iPhone:** Install the iOS app via [TestFlight](https://testflight.apple.com/join/1mxzWq51).

## How to Use

1. Launch ClipSync on Windows
2. Click the **Show QR** button at the top of the screen
3. Scan the QR code with the ClipSync app on your iPhone
4. Once connected, anything copied on either device is automatically synced to the other

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── screens/
│   └── home_screen.dart         # Main screen and UI logic
└── services/
    ├── websocket_server.dart    # WebSocket server for iPhone communication
    ├── clipboard_service.dart   # Clipboard monitoring and writing
    └── token_service.dart       # Auth token generation and validation
```

## Technical Details

- **Transport**: WebSocket on port 8765
- **Authentication**: 32-character random token generated at startup
- **Data format**: JSON; images are Base64-encoded
- **Clipboard detection**: 500 ms polling
