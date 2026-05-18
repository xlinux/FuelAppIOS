import Foundation
import CoreLocation
import UserNotifications
import SwiftUI

final class FuelGeofenceManager: NSObject {

    static let shared = FuelGeofenceManager()

    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    @AppStorage("fuelPriceNotificationsEnabled")
    private var fuelPriceNotificationsEnabled = true
    
    private override init() {
        super.init()
        locationManager.delegate = self
    }
 

    func requestPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("ERRORE PERMESSO NOTIFICHE:", error.localizedDescription)
            }

            print("PERMESSO NOTIFICHE:", granted)
        }

        locationManager.requestAlwaysAuthorization()
    }

    func registerGoodPriceStations(_ stations: [GasStation]) {
        stopMonitoringAllFuelRegions()

        let goodStations = stations
            .filter { station in
                station.price != nil && station.priceFreshnessDot == "🟢"
            }
            .sorted {
                ($0.price ?? Double.greatestFiniteMagnitude) <
                ($1.price ?? Double.greatestFiniteMagnitude)
            }
            .prefix(10)

        for station in goodStations {
            registerGeofence(for: station)
        }
    }

    func stopMonitoringAllFuelRegions() {
        for region in locationManager.monitoredRegions {
            if region.identifier.hasPrefix("fuel_station_") {
                locationManager.stopMonitoring(for: region)
            }
        }
    }

    private func registerGeofence(for station: GasStation) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("GEOFENCE NON DISPONIBILE")
            return
        }

        let region = CLCircularRegion(
            center: station.coordinate,
            radius: 400,
            identifier: geofenceIdentifier(for: station)
        )

        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)

        print("GEOFENCE REGISTRATA:", station.name, station.price ?? 0)
    }

    private func geofenceIdentifier(for station: GasStation) -> String {
        let safeName = station.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        let priceText = station.price == nil
            ? "noprice"
            : String(format: "%.3f", station.price!)

        return "fuel_station_\(safeName)_\(priceText)"
    }

    private func sendNotification(for region: CLRegion) {

        guard fuelPriceNotificationsEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Distributore conveniente vicino"
        content.body = notificationBody(from: region.identifier)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request)
    }

    private func notificationBody(from identifier: String) -> String {
        let cleaned = identifier
            .replacingOccurrences(of: "fuel_station_", with: "")
            .replacingOccurrences(of: "_", with: " ")

        return "Sei vicino a \(cleaned). Controlla il prezzo prima di passare oltre."
    }
}

extension FuelGeofenceManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("LOCATION AUTH:", manager.authorizationStatus.rawValue)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("fuel_station_") else {
            return
        }

        sendNotification(for: region)
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        print("ERRORE GEOFENCE:", region?.identifier ?? "unknown", error.localizedDescription)
    }
}
