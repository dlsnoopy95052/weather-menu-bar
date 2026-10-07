import AppKit
import Foundation
import Network

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
    private let pathMonitor = NWPathMonitor()
    private var networkAvailable = true

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

        // Check every minute whether the data is stale, rather than relying on a single
        // 15-minute timer: a fetch that fails (e.g. Wi-Fi still reconnecting after sleep)
        // is retried a minute later instead of leaving old data up for another 15 minutes.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfStale() }
        }
        timer?.tolerance = 10
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIfStale() }
        }
        // Refresh as soon as the network comes back (after sleep or a Wi-Fi drop).
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = available && !self.networkAvailable
                self.networkAvailable = available
                if cameBack { self.refreshIfStale() }
            }
        }
        pathMonitor.start(queue: .main)
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

    /// Refreshes unless a fetch is already running or the last successful one is recent.
    func refreshIfStale() {
        guard refreshTask == nil else { return }
        if let updated = weather?.updated, Date().timeIntervalSince(updated) < refreshInterval - 30 {
            return
        }
        refresh()
    }

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
            // A cancelled task has already been replaced by a newer one; leave that alone.
            if !Task.isCancelled { refreshTask = nil }
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
