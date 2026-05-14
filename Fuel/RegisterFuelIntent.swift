import AppIntents
import SwiftData
import CoreLocation

struct RegisterFuelIntent: AppIntent {
    static var title: LocalizedStringResource = "Registra benzina"

    @Parameter(title: "Importo")
    var amount: Double

    @Parameter(title: "Chilometri")
    var odometerKm: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let locationService = LocationService()

        let location = await locationService.requestLocation()
        let address = location == nil ? nil : await locationService.reverseGeocode(location!)
        let station = location == nil ? nil : await locationService.findNearbyGasStation(from: location!)

        let container = try ModelContainer(for: FuelEntry.self)
        let context = ModelContext(container)

        let entry = FuelEntry(
            amount: amount,
            odometerKm: odometerKm,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            address: address,
            stationName: station
        )

        context.insert(entry)
        try context.save()

        return .result(dialog: "Rifornimento registrato.")
    }
}
