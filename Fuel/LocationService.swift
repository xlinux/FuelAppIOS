import Foundation
import CoreLocation
import MapKit

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }

    func requestLocation() async -> CLLocation? {
        let status = manager.authorizationStatus

        print("LOCATION STATUS:", status.rawValue)

        if status == .denied || status == .restricted {
            print("LOCATION DENIED OR RESTRICTED")
            return nil
        }

        if status == .notDetermined {
            print("REQUESTING LOCATION PERMISSION")
            manager.requestWhenInUseAuthorization()

            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 300_000_000)

                let newStatus = manager.authorizationStatus
                print("NEW LOCATION STATUS:", newStatus.rawValue)

                if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                    break
                }

                if newStatus == .denied || newStatus == .restricted {
                    return nil
                }
            }
        }

        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            print("LOCATION NOT AUTHORIZED FINAL STATUS:", manager.authorizationStatus.rawValue)
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            print("REQUESTING CURRENT LOCATION")

            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        print("AUTH CHANGED:", status.rawValue)

        if status == .denied || status == .restricted {
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()

        print("DID UPDATE LOCATIONS:", locations)

        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()

        print("LOCATION ERROR:", error.localizedDescription)

        continuation?.resume(returning: nil)
        continuation = nil
    }

    func reverseGeocode(_ location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    print("REVERSE GEOCODE ERROR:", error.localizedDescription)
                }

                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let parts = [
                    placemark.thoroughfare,
                    placemark.subThoroughfare,
                    placemark.locality,
                    placemark.postalCode
                ].compactMap { $0 }

                continuation.resume(returning: parts.joined(separator: ", "))
            }
        }
    }

    func findNearbyGasStation(from location: CLLocation) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "benzinaio"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first?.name
        } catch {
            print("GAS STATION SEARCH ERROR:", error.localizedDescription)
            return nil
        }
    }
}
