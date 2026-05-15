import Foundation

final class FuelStationAPI {
    static let shared = FuelStationAPI()

    private init() {}

    func nearbyStations(
        lat: Double,
        lng: Double,
        fuelType: String,
        radiusMeters: Int = 5000
    ) async throws -> [FuelStationDTO] {

        var components = URLComponents(
            string: "\(APIConfig.baseURL)/api/stations/nearby"
        )!

        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "lng", value: "\(lng)"),
            URLQueryItem(name: "fuelType", value: fuelType),
            URLQueryItem(name: "radiusMeters", value: "\(radiusMeters)"),
            URLQueryItem(name: "maxPriceAgeDays", value: "7")
        ]

        let url = components.url!
        print("CALLING BACKEND:", url.absoluteString)
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([FuelStationDTO].self, from: data)
    }
    
    func bestStation(
        lat: Double,
        lng: Double,
        fuelType: String,
        liters: Double = 30,
        carKmPerLiter: Double = 15,
        radiusMeters: Int = 10000
    ) async throws -> FuelStationDTO {

        var components = URLComponents(
            string: "\(APIConfig.baseURL)/api/stations/best"
        )!

        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "lng", value: "\(lng)"),
            URLQueryItem(name: "fuelType", value: fuelType),
            URLQueryItem(name: "liters", value: "\(liters)"),
            URLQueryItem(name: "carKmPerLiter", value: "\(carKmPerLiter)"),
            URLQueryItem(name: "radiusMeters", value: "\(radiusMeters)")
        ]

        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        return try JSONDecoder().decode(FuelStationDTO.self, from: data)
    }
    func bestStations(
        lat: Double,
        lng: Double,
        fuelType: String,
        liters: Double = 30,
        carKmPerLiter: Double = 15,
        radiusMeters: Int = 10000,
        limit: Int = 5
    ) async throws -> [FuelStationDTO] {

        var components = URLComponents(
            string: "\(APIConfig.baseURL)/api/stations/best-options"
        )!

        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(lat)"),
            URLQueryItem(name: "lng", value: "\(lng)"),
            URLQueryItem(name: "fuelType", value: fuelType),
            URLQueryItem(name: "liters", value: "\(liters)"),
            URLQueryItem(name: "carKmPerLiter", value: "\(carKmPerLiter)"),
            URLQueryItem(name: "radiusMeters", value: "\(radiusMeters)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "maxPriceAgeDays", value: "7")
        ]

        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        return try JSONDecoder().decode([FuelStationDTO].self, from: data)
    }
}
