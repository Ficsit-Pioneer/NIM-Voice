import Foundation
import CoreLocation

/// One-shot, approximate location → "City, Region, Country" used to ground
/// location-relevant web searches ("nearby", "around here").
///
/// Defensive by design: a single in-flight request at a time, a guarded
/// continuation that can only resume once, and a hard timeout so a missing fix
/// never hangs the conversation. Returns nil when denied or unavailable.
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Returns a short place description like "Austin, Texas, United States", or nil.
    func placeDescription() async -> String? {
        guard let location = await currentLocation() else { return nil }
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.locality, placemark.administrativeArea, placemark.country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func currentLocation() async -> CLLocation? {
        guard continuation == nil else { return nil }          // one request at a time
        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = cont
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()       // didChange callback triggers requestLocation
            } else {
                manager.requestLocation()
            }
            // Hard timeout — resume(nil) is a no-op if the fix already arrived.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                self.deliver(nil)
            }
        }
    }

    /// Resumes the pending continuation exactly once.
    private func deliver(_ location: CLLocation?) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: location)
    }

    fileprivate func handleAuthorizationChange() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            deliver(nil)
        default:
            break
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.handleAuthorizationChange() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.deliver(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.deliver(nil) }
    }
}
