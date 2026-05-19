# ByeTunes 🎵

**Say goodbye to iTunes sync!**

ByeTunes is a native iOS app that lets you inject music (MP3, M4A, FLAC, WAV) and ringtones directly into your device's media library—without needing a computer connection for every sync. It communicates directly with the iOS media database, giving you the power to manage your music on your terms.

## Features

-   **Direct Music Injection**: Add songs to your Apple Music library without a PC.
-   (DISABLED FOR NOW) **Ringtone Manager**: Inject custom ringtones (`.m4r` and `.mp3` auto-conversion).
-   **Playlist Support**: Create and manage playlists on the fly.
-   **No Computer Needed** (after setup): Once paired, you're free!
-   **Metadata Editing**: Auto-fetched from iTunes or Deezer.

## Compilation Instructions

To build ByeTunes yourself, you'll need a Mac with Xcode.

### Prerequisites

1.  **Xcode**: Version 15+ recommended.
2.  **iOS Device**: Running iOS 16.0 or later.

### External Libraries

ByeTunes relies on `idevice` (a `libimobiledevice` alternative) to talk to the iOS internal file system. **These files are NOT included in this repository** for licensing/size reasons.

To compile the app, you need to obtain these two files and place them in the `MusicManager/` directory:

1.  `libidevice_ffi.a` (Static Library)
2.  `idevice.h` (Header File)

You can find idevice and compile it from here: [https://github.com/jkcoxson/idevice](https://github.com/jkcoxson/idevice)

*If you don't have these files, the project will not compile.*

### FFmpegKit (Convert tab)

The **Convert** tab uses [ffmpeg-kit-spm](https://github.com/tylerjonesio/ffmpeg-kit-spm) (Swift Package Manager) for Opus/Ogg and other formats that iOS cannot decode natively. Xcode resolves this dependency automatically on first open/build.

**Note:** FFmpegKit is LGPL-licensed. Review license terms before distributing builds.

### Build Steps

1.  Install Rust:
    ```bash
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    ```
2.  Add the ios Arch:
    ```bash
    rustup target add aarch64-apple-ios
    ```
    
3.  Install Xcode Command Line Tools if you don't have it already installed:
    ```bash
    xcode-select --install
    ```

4.  Clone the repo:
    ```bash
    git clone https://github.com/jkcoxson/idevice
    ```

5.  Set a deployment target:
    ```bash
    export IPHONEOS_DEPLOYMENT_TARGET=xx.x
    ```

6.  Run the cargo build:
    ```bash
    cargo build --release --package idevice-ffi --target aarch64-apple-ios
    ```
Inside the idevice folder find: idevice.h and libidevice_ffi.a. Move them inside the project in Xcode, make sure you create **Bridging-Header.h**
Inside your Xcode project and make sure you add:

 ```bash
    #import "idevice.h"
```

**In Project Settings > Build Phases > Link Binary With Libraries, make sure libidevice_ffi.a is listed.**

### One-command IPA for Signulous (sideloading)

To build an **unsigned** device IPA you can upload to [Signulous](https://www.signulous.com/sign-apps) (or similar services), run from the repo root:

```bash
chmod +x setup-build-env.sh build-ipa.sh scripts/*.sh   # first time only
./setup-build-env.sh   # Xcode check, Rust, Swift packages (safe to re-run)
./build-ipa.sh
```

The script will:

1. Install **Rust** + `aarch64-apple-ios` target if needed (to compile `libidevice_ffi.a`)
2. Clone/build [idevice](https://github.com/jkcoxson/idevice) when `MusicManager/libidevice_ffi.a` is missing
3. Create `Bridging-Header.h` if needed
4. Resolve **FFmpegKit** via Swift Package Manager
5. Build **Release** for a physical iPhone (`arm64`, iOS 16.0+)
6. Write `dist/ByeTunes-<version>-unsigned.ipa`

Options:

| Flag / env | Purpose |
|------------|---------|
| `./build-ipa.sh --clean` | Remove `build/` and `dist/` before building |
| `./build-ipa.sh --skip-idevice` | Skip Rust/idevice step if you already placed the three files in `MusicManager/` |
| `IDEVICE_SRC_DIR=~/src/idevice` | Use an existing idevice clone instead of `build/deps/idevice` |

**Requirements:** macOS, Xcode 15+ (tested through Xcode 26), internet on first run (SPM + idevice clone).

**Note:** The IPA is **unsigned** on purpose — Signulous re-signs it for your registered device. The app is already configured for sideloading file imports (`asCopy: true` in the document picker).

## How to Use

1. **LocalDevVPN**:
    - Download LocalDevVPN from the App Store/Altstore PAL https://apps.apple.com/us/app/localdevvpn/id6755608044.
    - Open it and tap Connect, you will need an active connection to import the pairing file inside the app.

2.  **Pairing**:
    -   On first launch, you'll see an "Import Pairing File" screen.
    -   You need to get a `pairing file`.
    -   Download idevice_pair refer to https://github.com/jkcoxson/idevice_pair .
    -   Generate you `pairing file`.
    -   Export it from your computer and Airdrop/Save it to your iPhone.
    -   Import it into ByeTunes.
      
3.  **Add Music**:
    -   Tap "Add Songs" and select files from your Files app.
    -   Hit "Inject to Device" and watch the magic happen.

3b. **Convert incompatible audio (Opus, Ogg, FLAC, etc.)**:
    -   Open the **Convert** tab, select multiple files, choose **ALAC (.m4a)** or **AAC (.m4a)**.
    -   Tap **Convert**, then **Add Converted to Music Queue** before injecting.
      
4.  **Ringtones**:
    -   Go to the Ringtones tab, add your file, and inject!

## Notes

-   **Signed Apps**: If you install this via a signing service (Signulous, AltStore, etc.), the app includes a fix (`asCopy: true`) to ensure file importing works correctly without crashing.
-   **Backup**: Always good to have a backup of your music library before messing with database injection!

## Support & Bug Reporting

Found a bug? We'd love to fix it!

1.  **Report Issues**: Open a ticket on [GitHub Issues](https://github.com/EduAlexxis/ByeTunes/issues).
2.  **Join the Community**: Chat with us on [Discord](https://discord.gg/dDQ4P4SyKJ).
3.  **Attach Debug Logs**:
    *   If you are experiencing injection failures, please use the **Debug Options** under delte library inside settings.
    *   This includes a "Debug Logs" screen where you can copy the app logs.
    *   Please attach these logs to your issue report—they help us solve problems much faster!

---
*Created with ❤️ by EduAlexxis*
