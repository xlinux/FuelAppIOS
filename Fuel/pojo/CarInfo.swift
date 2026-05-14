import Foundation

struct CarInfo: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var fuelTypeRaw: String

    var fuelType: FuelType {
        get {
            FuelType(rawValue: fuelTypeRaw) ?? .benzina
        }
        set {
            fuelTypeRaw = newValue.rawValue
        }
    }
}
