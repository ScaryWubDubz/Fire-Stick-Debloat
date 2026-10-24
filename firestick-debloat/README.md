# Fire Stick: Clean & Minimal

Takes about 20 minutes. You need a computer on the same Wi-Fi as the Fire Stick.

## 1. Turn off ads and tracking (on the TV, no tools needed)

**Settings → Preferences**
- Featured Content → **Allow Video Autoplay: OFF**, **Allow Audio Autoplay: OFF**, **Sponsored Content: OFF** (when shown)
- Privacy Settings → **Device Usage Data: OFF**, **Collect App Usage Data: OFF**, **Interest-based Ads: OFF**
- Data Monitoring → **ON** (it stops some background streaming)
- Notification Settings → turn off **App Notifications** for everything you don't need

**Settings → Display & Sounds → Screensaver** → pick **Off**, or a plain photo album.
**Settings → Applications → Appstore → Automatic Updates** → keep **ON** for the apps you keep.

## 2. Enable ADB on the stick

1. Settings → My Fire TV → About → click **your device name 7 times** (turns on Developer Options).
2. Settings → My Fire TV → Developer Options → **ADB Debugging: ON**.
3. Settings → My Fire TV → About → Network → write down the **IP address**.

## 3. Install ADB on your computer

- **Mac:** `brew install android-platform-tools`
- **Windows:** nothing to install. The tool offers to download Google's platform-tools for you the first time it runs. Skip step 4 and use the Windows steps below.
- **Linux:** `sudo apt install adb`

## 4. Run the debloater

```bash
./debloat.sh 192.168.1.50 --dry-run   # preview only, changes nothing
./debloat.sh 192.168.1.50             # do it
```

- On the first connection, your TV asks you to allow debugging. Tick **Always allow** and select OK.
- The script removes Amazon's ad and telemetry services without asking.
- Then it asks about each Amazon app (Prime Video, Freevee, Music…) and each app you installed. Answer **y** only for apps you want **gone**.
- Add `--block-updates` to stop Fire OS updates from bringing ads back. The trade-off: you also stop getting security patches.
- Apps are **disabled, not deleted**. To undo everything, run `./restore.sh 192.168.1.50`. To bring back one app, add its name: `./restore.sh 192.168.1.50 com.amazon.cloud9`.

Restart afterwards: `adb -s 192.168.1.50:5555 reboot`

### Windows: the double-click version

1. Save `Start-Here.bat` and `FireStick.ps1` in the same folder. Your Downloads folder works.
2. Double-click **Start-Here.bat**. If Windows says "Windows protected your PC", click **More info → Run anyway**.
3. Type your Fire Stick's IP address. On first connection, the TV shows a popup: tick **Always allow** and select **OK**.
4. Choose **1** to preview, **2** to clean up, or **3** to undo everything. Option **7** walks you through downloading and installing Projectivy, and **4** makes it your home screen.

## 5. The clean look: Projectivy Launcher (optional, recommended)

Even with the ads gone, the Amazon home screen is busy. Projectivy shows just a row of your apps over a wallpaper you pick.

1. Install **Downloader** from the Appstore. In Settings → My Fire TV → Developer Options, set **Install Unknown Apps** to ON for Downloader.
2. Projectivy Launcher is also in the Appstore on many regions. Search "Projectivy". If it's not there, install it from its official page through Downloader.
3. In Projectivy settings:
   - **General → Override current launcher: ON**, then grant the accessibility permission it asks for. This makes the Home button open Projectivy.
   - **Appearance:** pick one wallpaper (a dark, low-contrast photo or a solid color works best), turn **wallpaper dimming** up a little, and set **card style** to icons only.
   - **Channels / Recommendations: OFF**, leaving just one row of your apps.
   - Hide anything you don't open from the app list (long-press an app → Hide).
4. **Do not** remove `com.amazon.tv.launcher`. Projectivy sits on top of it, and the script won't touch it.

Result: you boot to one dark wallpaper and a single row of the apps you use. No banners or autoplay trailers.

## Troubleshooting

- **"failed … wouldn't allow it":** newer Fire OS protects some system apps. That's harmless. The script skips them.
- **Something broke after removal:** run `./restore.sh <ip>` and reboot.
- **Home button opens Amazon's home again after an update:** open Projectivy and turn **Override current launcher** back on.
