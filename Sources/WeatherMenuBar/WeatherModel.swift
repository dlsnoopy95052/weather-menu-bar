import AppKit
import Foundation

struct CurrentWeather {
    var temperature: Double
    var feelsLike: Double
    var high: Double
    var low: Double
    var humidity: Int
    var windSpeed: Double
    var code: Int
    var isDay: Bool
    var updated: Date

    var condition: String { WeatherCode.description(code) }
}

struct ManualCity: Codable {
    var name: String
    var latitude: Double
    var longitude: Double
}

@MainActor
final class WeatherModel: ObservableObject {
    @Published var weather: CurrentWeather?
    @Published var locationName = "Locating…"
    @Published var status = "Loading weather…"
    @Published var errorMessage: String?
    @Published var useFahrenheit: Bool {
        didSet {
            UserDefaults.standard.set(useFahrenheit, forKey: "useFahrenheit")
            refresh()
        }
    }
    @Published var manualCity: ManualCity? {
        didSet {
            if let manualCity, let data = try? JSONEncoder().encode(manualCity) {
                UserDefaults.standard.set(data, forKey: "manualCity")
            } else {
                UserDefaults.standard.removeObject(forKey: "manualCity")
            }
        }
    }

    private let locator = Locator()
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 15 * 60

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "useFahrenheit") != nil {
            useFahrenheit = defaults.bool(forKey: "useFahrenheit")
        } else {
            useFahrenheit = Locale.current.measurementSystem == .us
        }
        if let data = defaults.data(forKey: "manualCity") {
            manualCity = try? JSONDecoder().decode(ManualCity.self, from: data)
        }

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Give the network a moment to come back after sleep.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                self?.refresh()
            }
        }
        refresh()
    }

    // MARK: - Display

    var menuBarTitle: String {
        guard let weather else { return "--°" }
        return "\(Int(weather.temperature.rounded()))°"
    }

    var symbolName: String {
        guard let weather else { return "cloud.sun" }
        return WeatherCode.symbol(weather.code, isDay: weather.isDay)
    }

    func format(_ temp: Double) -> String {
        "\(Int(temp.rounded()))°\(useFahrenheit ? "F" : "C")"
    }

    // MARK: - Actions

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let place = try await resolveLocation()
                locationName = place.name
                let result = try await WeatherAPI.fetch(
                    latitude: place.latitude, longitude: place.longitude, fahrenheit: useFahrenheit)
                guard !Task.isCancelled else { return }
                weather = result
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                status = "Weather unavailable"
            }
        }
    }

    func useAutomaticLocation() {
        manualCity = nil
        refresh()
    }

    func promptForCity() {
        let alert = NSAlert()
        alert.messageText = "Set City"
        alert.informativeText = "Enter a city name (e.g. \"Boston\" or \"Paris, France\")."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = manualCity?.name ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task {
            do {
                manualCity = try await WeatherAPI.geocode(query)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Location

    private func resolveLocation() async throws -> ManualCity {
        if let manualCity { return manualCity }

        // Try Location Services first, then fall back to IP-based lookup.
        if let coordinate = await locator.currentLocation() {
            let name = await locator.placeName(for: coordinate) ?? "Current Location"
            return ManualCity(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return try await WeatherAPI.ipLocation()
    }
}
