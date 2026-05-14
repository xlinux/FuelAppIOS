import Foundation

struct FuelStationDTO: Codable, Identifiable {
    let id: String?
    let externalId: String?
    let name: String?
    let brand: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let fuelType: String
    let price: Double?
    let selfService: Bool?
    let priceUpdatedAt: String?
}
