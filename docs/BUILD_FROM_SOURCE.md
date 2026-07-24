# Build TixisBirdview from Source

You do not need to know Swift or use Xcode day to day. You only need Xcode once
to compile the app on your Mac.

## Before you start

- A Mac with a current macOS version.
- An Apple Account. A free account is sufficient for a personal development
  build.
- Around 15 GB of free disk space for Xcode.

## 1. One-time Xcode setup

1. Install **Xcode** from the Mac App Store.
2. Open Xcode once, accept its license, then open **Xcode > Settings >
   Accounts**.
3. Add your Apple Account. Xcode will show it as a Personal Team unless you
   have a paid Apple Developer Program membership.
4. Download the TixisBirdview source from GitHub with **Code > Download ZIP**,
   then double-click the downloaded ZIP file.

## 2. Set your Team ID

TixisBirdview needs a 10-character Team ID only to sign the app for your own
Mac. It is not a password and is stored only in your ignored local build file.

### Paid Apple Developer Program membership

Sign in at [Apple Developer Account](https://developer.apple.com/account/),
open **Membership details**, and copy the 10-character **Team ID**. Then follow
**Save the ID locally** below.

### Free Personal Team

1. Double-click `TixisBirdview.xcodeproj` to open it in Xcode.
2. Select the **TixisBirdview** target, open **Signing & Capabilities**, and
   choose your **Personal Team** from the **Team** menu.
3. Quit Xcode and run `./build-and-install.sh`. The script reads the Team ID
   from the team you selected, so no TextEdit step is needed.

If you want to see the value yourself, run this optional command in Terminal:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -showBuildSettings \
  -project TixisBirdview.xcodeproj \
  -scheme TixisBirdview | \
awk -F ' = ' '/^[[:space:]]*DEVELOPMENT_TEAM =/ { print $2; exit }'
```

It prints the Team ID. If it prints nothing, reopen Xcode and make sure your
Personal Team is selected for the target.

Do **not** use `security find-identity` for this: the ID displayed on an Apple
Development certificate can identify the team member rather than the developer
team.

### Save the ID locally

This is required for a paid membership and optional for a Personal Team. From
the extracted project folder, run:

```sh
cp build.local.env.example build.local.env
open -e build.local.env
```

TextEdit opens the file. Replace `ABCDEFGHIJ` with the Team ID you copied, save,
and close TextEdit. `build.local.env` is ignored by Git and will never be
included when you share or update the project.

## 3. Build and install

1. Open **Terminal** (`Applications > Utilities > Terminal`).
2. Type `cd ` (including the trailing space), then drag the extracted
   `TixisBirdview` folder into the Terminal window and press Return.
3. Run:

   ```bash
   ./build-and-install.sh
   ```

4. Enter your Mac administrator password when asked. It is used only to place
   the finished app in `/Applications`.
5. Start **TixisBirdview** from Applications and complete the
   [first-time setup](../README.md#first-time-setup).

## If the build fails

| Message | Fix |
| --- | --- |
| `Xcode was not found` | Install the full Xcode app, open it once, then try again. |
| `No valid Apple Developer Team ID was configured` | Return to **Set your Team ID** above, then save the 10-character value in `build.local.env`. |
| `No signing certificate` | In Xcode, add your Apple Account under Settings > Accounts. If it persists, open `TixisBirdview.xcodeproj`, select the **TixisBirdview** target, choose your Personal Team in **Signing & Capabilities**, then retry. |
| `Permission denied: ./build-and-install.sh` | Run `chmod +x build-and-install.sh` once, then run the script again. |
| App cannot connect | This is separate from building: confirm the Frigate URL, login, and macOS TLS trust in TixisBirdview's Settings. |

## Updating a source build

Download the newer source ZIP, repeat the build command, and allow macOS to
replace the existing app. Your TixisBirdview settings and Keychain password
remain on your Mac.
