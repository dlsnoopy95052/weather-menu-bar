# Weather Menu Bar

Shows the current temperature and a condition icon in the macOS menu bar (macOS 13+).
Uses [Open-Meteo](https://open-meteo.com), so no API key is needed. Refreshes every 15 minutes and after the Mac wakes.

## Build & install

    ./build.sh            # builds build/WeatherMenuBar.app
    ./build.sh --install  # also copies to ~/Applications and launches it

It needs only the Xcode Command Line Tools, not the full Xcode app.

## Menu

- Details: condition, feels-like, high/low, humidity, wind
- **Refresh Now** (⌘R)
- **Units**: °F / °C
- **Location**: use current location (Location Services, falling back to IP lookup), or set a city
- **Launch at Login**
