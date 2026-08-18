# Privacy

TixisBirdview does not contain analytics, advertising, tracking, or telemetry.
It does not operate an account service and does not send camera images, event
details, credentials, or configuration to the TixisBirdview maintainers.

## Data stored on the Mac

- App preferences, such as popup behavior and selected classifications, are
  stored in the app's private `UserDefaults` container.
- Frigate and MQTT passwords are stored in the macOS Keychain.
- TixisBirdview does not create a cloud copy of these values.

Use **Settings > General > App data > Delete All App Data…** to remove all
TixisBirdview preferences and every Frigate and MQTT password saved by the app.
The app quits after deletion so the next launch starts with clean defaults.
Removing the app bundle alone does not remove macOS Keychain items; use this
action before uninstalling if those credentials should also be deleted.

## Network connections

TixisBirdview connects only to services needed for the features the user
configures:

- the user's Frigate server;
- the user's MQTT broker when MQTT event delivery is selected; and
- GitHub's public Releases API when an automatic or manual update check runs.

The update request identifies the installed TixisBirdview version in its
standard HTTP user-agent. It does not include Frigate or MQTT settings,
credentials, camera names, events, images, cookies, or other app data.
Automatic update checks can be disabled under **Settings > General**.

An update check only reports that a newer release exists. TixisBirdview never
downloads or installs an update without the user's action.
