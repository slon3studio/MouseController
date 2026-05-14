# MouseController Mac Companion App

MouseControllerMac is the companion macOS application for the MouseController iPhone app.

It allows your iPhone to control your Mac cursor, clicking, scrolling, and keyboard input over the same local network.

## Requirements

- macOS
- MouseController iPhone app
- iPhone and Mac connected to the same Wi-Fi network or personal hotspot
- Accessibility permission enabled on macOS

## Installation

1. Download the latest `MouseControllerMac.zip` file from the Releases page.
2. Unzip the file.
3. Move `MouseControllerMac.app` to your Applications folder.
4. Open the app.

If macOS blocks the app the first time:

1. Right-click `MouseControllerMac.app`.
2. Click `Open`.
3. Confirm by clicking `Open` again.

## Accessibility Permission

MouseControllerMac needs Accessibility permission to control the cursor and keyboard.

To enable it:

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Open `Accessibility`.
4. Add or enable `MouseControllerMac`.

Without this permission, cursor movement and keyboard input will not work.

## How to Connect

1. Launch `MouseControllerMac` on your Mac.
2. The app will display your local IP address.
3. Open the MouseController iPhone app.
4. Enter the IP address shown in the Mac app.
5. Tap `Connect`.
6. Use your iPhone as a wireless trackpad and keyboard.

## Features

- Cursor movement
- Tap to click
- Two-finger scrolling
- Live keyboard input
- Local network connection
- No external servers

## Privacy

MouseControllerMac communicates only with the iPhone app over your local network.

It does not collect, store, track, or send personal data to external servers.

## Troubleshooting

### The iPhone app cannot connect

Check that:

- Both devices are on the same Wi-Fi network or hotspot
- The Mac app is running
- The correct IP address is entered
- Firewall settings are not blocking local connections

### Cursor movement does not work

Check that:

- Accessibility permission is enabled
- The Mac app has been restarted after enabling permission

### macOS says the app cannot be opened

Right-click the app and select `Open`.

This may happen because the app is distributed directly through GitHub.

## Notes

This macOS app is required for the MouseController iPhone app to function.
The iPhone app sends local control commands, and the Mac app performs the cursor and keyboard actions.
