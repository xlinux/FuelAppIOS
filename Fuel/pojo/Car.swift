import Foundation
import SwiftData

@Model
final class Car {
    var id: UUID
    var name: String
    var fuelTypeRaw: String

    init(
        id: UUID = UUID(),
        name: String,
        fuelTypeRaw: String = FuelType.benzina.rawValue
    ) {
        self.id = id
        self.name = name
        self.fuelTypeRaw = fuelTypeRaw
    }
}
