import CoreLocation

/// One-shot wrapper around CLLocationManager. Returns nil if permission is
/// denied, Location Services are off, or no fix arrives within the timeout.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation(timeout: TimeInterval = 10) async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        default:
            break
        }

        // Only one request in flight at a time.
        if let continuation {
            continuation.resume(returning: nil)
            self.continuation = nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            Task { @MainActor in
                // Allow extra time when the user is looking at the permission prompt.
                let wait = manager.authorizationStatus == .notDetermined ? 60 : timeout
                try? await Task.sleep(for: .seconds(wait))
                self.finish(nil)
            }
        }
    }

    func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        return placemark.locality ?? placemark.administrativeArea ?? placemark.country
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorized:
                manager.requestLocation()
            case .denied, .restricted:
                self.finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
