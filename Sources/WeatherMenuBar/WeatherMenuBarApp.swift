import SwiftUI
import ServiceManagement

@main
struct WeatherMenuBarApp: App {
    @StateObject private var model = WeatherModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.symbolName)
                Text(model.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var model: WeatherModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if let w = model.weather {
            Text("\(model.locationName)")
            Text("\(w.condition), \(model.format(w.temperature))")
            Text("Feels like \(model.format(w.feelsLike))")
            Text("High \(model.format(w.high))  ·  Low \(model.format(w.low))")
            Text("Humidity \(w.humidity)%  ·  Wind \(Int(w.windSpeed.rounded())) \(model.useFahrenheit ? "mph" : "km/h")")
            Text("Updated \(w.updated.formatted(date: .omitted, time: .shortened))")
        } else {
            Text(model.status)
        }
        if let error = model.errorMessage {
            Text("⚠️ \(error)")
        }

        Divider()

        Button("Refresh Now") { model.refresh() }
            .keyboardShortcut("r")

        Picker("Units", selection: $model.useFahrenheit) {
            Text("°F").tag(true)
            Text("°C").tag(false)
        }

        Menu("Location") {
            Button("Use Current Location") { model.useAutomaticLocation() }
            Button("Set City…") { model.promptForCity() }
            if model.manualCity != nil {
                Text("Using: \(model.locationName)")
            } else {
                Text("Using: automatic")
            }
        }

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    model.errorMessage = "Launch at login: \(error.localizedDescription)"
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
