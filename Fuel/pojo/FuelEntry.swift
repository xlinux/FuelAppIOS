import Foundation
import SwiftData

@Model
final class FuelEntry {
    var date: Date
    var amount: Double
    var odometerKm: Double

    var latitude: Double?
    var longitude: Double?
    var address: String?
    var stationName: String?

    var carName: String?
    var fuelTypeRaw: String?
    var gpsEstimatedKm: Double?
    var fuelPrice: Double?
    init(
        date: Date = .now,
        amount: Double,
        odometerKm: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        stationName: String? = nil,
        carName: String? = nil,
        fuelTypeRaw: String? = nil,
        gpsEstimatedKm: Double? = nil,
        fuelPrice: Double? = nil
    ) {
        self.date = date
        self.amount = amount
        self.odometerKm = odometerKm

        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.stationName = stationName

        self.carName = carName
        self.fuelTypeRaw = fuelTypeRaw
        self.gpsEstimatedKm = gpsEstimatedKm
        self.fuelPrice = fuelPrice
    }
}
