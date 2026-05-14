import Foundation
import SwiftData

@Model
final class AppSettings {
    var gpsTrackingEnabled: Bool
    var estimatedKmSinceLastRefuel: Double

    var fuelTypeRaw: String
    var carName: String

    init(
        gpsTrackingEnabled: Bool = false,
        estimatedKmSinceLastRefuel: Double = 0,
        fuelTypeRaw: String = FuelType.benzina.rawValue,
        carName: String = ""
    ) {
        self.gpsTrackingEnabled = gpsTrackingEnabled
        self.estimatedKmSinceLastRefuel = estimatedKmSinceLastRefuel
        self.fuelTypeRaw = fuelTypeRaw
        self.carName = carName
    }

    
}

