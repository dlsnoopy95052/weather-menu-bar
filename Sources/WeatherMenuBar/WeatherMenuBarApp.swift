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
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var model: WeatherModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let w = model.weather {
                current(w)
                if !w.forecast.isEmpty {
                    Divider()
                    forecast(w.forecast)
                }
            } else {
                Text(model.status).foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            controls
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Current conditions

    @ViewBuilder
    private func current(_ w: CurrentWeather) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.locationName)
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: WeatherCode.symbol(w.code, isDay: w.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 40))
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.format(w.temperature))
                        .font(.system(size: 36, weight: .semibold))
                        .monospacedDigit()
                    Text(w.condition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("H \(model.format(w.high))")
                    Text("L \(model.format(w.low))")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .monospacedDigit()
            }

            HStack(spacing: 0) {
                stat("Feels like", model.format(w.feelsLike))
                stat("Humidity", "\(w.humidity)%")
                stat("Wind", "\(Int(w.windSpeed.rounded())) \(model.useFahrenheit ? "mph" : "km/h")")
            }

            Text("Updated \(w.updated.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Forecast

    @ViewBuilder
    private func forecast(_ days: [DailyForecast]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next \(days.count) Days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(days, id: \.date) { day in
                HStack(spacing: 8) {
                    Text(day.dayName)
                        .frame(width: 40, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 24)
                        .help(WeatherCode.description(day.code))
                    Text(rainText(day))
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .frame(width: 40, alignment: .leading)
                    Spacer()
                    Text(model.format(day.low))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                    Text(model.format(day.high))
                        .fontWeight(.medium)
                        .frame(width: 52, alignment: .trailing)
                }
                .monospacedDigit()
            }
        }
    }

    private func rainText(_ day: DailyForecast) -> String {
        guard let chance = day.precipitationChance, chance >= 10 else { return "" }
        return "\(chance)%"
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Units", selection: $model.useFahrenheit) {
                    Text("°F").tag(true)
                    Text("°C").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)

                Spacer()

                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Refresh Now")

                Menu {
                    Button("Use Current Location") { model.useAutomaticLocation() }
                    Button("Set City…") { model.promptForCity() }
                    Divider()
                    Text(model.manualCity != nil ? "Using: \(model.locationName)" : "Using: automatic")
                } label: {
                    Image(systemName: "location")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Location")
            }

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
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

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}
