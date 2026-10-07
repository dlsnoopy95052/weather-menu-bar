import Foundation

/// Open-Meteo (https://open-meteo.com) — free, no API key required.
enum WeatherAPI {
    struct APIError: LocalizedError {
        var errorDescription: String?
    }

    static func fetch(latitude: Double, longitude: Double, fahrenheit: Bool) async throws -> CurrentWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let apparent_temperature: Double
                let relative_humidity_2m: Int
                let weather_code: Int
                let wind_speed_10m: Double
                let is_day: Int
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }

        let r: Response = try await get(components.url!)
        return CurrentWeather(
            temperature: r.current.temperature_2m,
            feelsLike: r.current.apparent_temperature,
            high: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
            low: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
            humidity: r.current.relative_humidity_2m,
            windSpeed: r.current.wind_speed_10m,
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            updated: Date()
        )
    }

    static func geocode(_ query: String) async throws -> ManualCity {
        // Open-Meteo matches on the place name only, so search with the part before
        // any comma and use the rest (e.g. "France" in "Paris, France") to pick a result.
        let parts = query.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: parts[0]),
            .init(name: "count", value: "10"),
        ]

        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
                let country: String?
                let country_code: String?
                let admin1: String?
            }
            let results: [Result]?
        }

        let r: Response = try await get(components.url!)
        let results = r.results ?? []
        let qualifier = parts.dropFirst().first?.lowercased()
        let match = results.first { result in
            guard let qualifier else { return true }
            return [result.country, result.country_code, result.admin1]
                .compactMap { $0?.lowercased() }
                .contains { $0 == qualifier || $0.hasPrefix(qualifier) }
        } ?? results.first

        guard let match else {
            throw APIError(errorDescription: "City \"\(query)\" not found")
        }
        let name = [match.name, match.admin1 ?? match.country].compactMap { $0 }.joined(separator: ", ")
        return ManualCity(name: name, latitude: match.latitude, longitude: match.longitude)
    }

    /// Approximate location from the public IP address (ipwho.is — free, no key).
    static func ipLocation() async throws -> ManualCity {
        struct Response: Decodable {
            let success: Bool
            let city: String?
            let latitude: Double?
            let longitude: Double?
        }
        let r: Response = try await get(URL(string: "https://ipwho.is/")!)
        guard r.success, let lat = r.latitude, let lon = r.longitude else {
            throw APIError(errorDescription: "Couldn't determine location. Use Location → Set City…")
        }
        return ManualCity(name: r.city ?? "Current Location", latitude: lat, longitude: lon)
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError(errorDescription: "Server returned HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with Hail"
        default: return "Unknown"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun"
        }
    }
}
