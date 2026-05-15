import Foundation

struct RemoteCarDTO: Codable, Identifiable {
    let id: String
    let name: String
    let fuelType: String
    let defaultCar: Bool?
    let createdAt: String?
}

struct RemoteCarRequest: Codable {
    let name: String
    let fuelType: String
    let defaultCar: Bool
}

struct RemoteFuelEntryDTO: Codable, Identifiable {
    let id: String
    let carId: String?
    let carName: String?
    let fuelType: String?
    let amount: Double
    let odometerKm: Double
    let fuelPrice: Double?
    let gpsEstimatedKm: Double?
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let stationName: String?
    let entryDate: String?
    let createdAt: String?
}

struct RemoteFuelEntryRequest: Codable {
    let carId: String?
    let carName: String?
    let fuelType: String?
    let amount: Double
    let odometerKm: Double
    let fuelPrice: Double?
    let gpsEstimatedKm: Double?
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let stationName: String?
    let entryDate: String?
}

final class UserDataAPI {
    static let shared = UserDataAPI()

    private init() {}

    private var deviceId: String {
        DeviceIdProvider.shared.getDeviceId()
    }

    func fetchCars() async throws -> [RemoteCarDTO] {
        let url = try makeURL(path: "/api/me/cars")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(to: &request)

        let data = try await perform(request)
        return try JSONDecoder().decode([RemoteCarDTO].self, from: data)
    }

    func createCar(name: String, fuelType: String, defaultCar: Bool) async throws -> RemoteCarDTO {
        let url = try makeURL(path: "/api/me/cars")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)

        let body = RemoteCarRequest(
            name: name,
            fuelType: fuelType.uppercased(),
            defaultCar: defaultCar
        )

        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request)
        return try JSONDecoder().decode(RemoteCarDTO.self, from: data)
    }

    func updateCar(id: String, name: String, fuelType: String, defaultCar: Bool) async throws -> RemoteCarDTO {
        let url = try makeURL(path: "/api/me/cars/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        addHeaders(to: &request)

        let body = RemoteCarRequest(
            name: name,
            fuelType: fuelType.uppercased(),
            defaultCar: defaultCar
        )

        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request)
        return try JSONDecoder().decode(RemoteCarDTO.self, from: data)
    }

    func deleteCar(id: String) async throws {
        let url = try makeURL(path: "/api/me/cars/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(to: &request)

        _ = try await perform(request)
    }

    func setDefaultCar(id: String) async throws {
        let url = try makeURL(path: "/api/me/cars/\(id)/default")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        addHeaders(to: &request)

        _ = try await perform(request)
    }

    func fetchFuelEntries() async throws -> [RemoteFuelEntryDTO] {
        let url = try makeURL(path: "/api/me/fuel-entries")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(to: &request)

        let data = try await perform(request)
        return try JSONDecoder().decode([RemoteFuelEntryDTO].self, from: data)
    }

    func createFuelEntry(_ body: RemoteFuelEntryRequest) async throws -> RemoteFuelEntryDTO {
        let url = try makeURL(path: "/api/me/fuel-entries")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(request)
        return try JSONDecoder().decode(RemoteFuelEntryDTO.self, from: data)
    }

    func deleteFuelEntry(id: String) async throws {
        let url = try makeURL(path: "/api/me/fuel-entries/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(to: &request)

        _ = try await perform(request)
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: "\(APIConfig.baseURL)\(path)") else {
            throw URLError(.badURL)
        }

        return url
    }

    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("USER DATA API ERROR", httpResponse.statusCode, body)
            throw URLError(.badServerResponse)
        }

        return data
    }
}
