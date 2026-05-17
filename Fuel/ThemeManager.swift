import SwiftUI

struct ThemeManager {

    static func tintColor(
        carsJson: String,
        selectedCarId: String
    ) -> Color {

        guard
            let data = carsJson.data(using: .utf8),
            let cars = try? JSONDecoder().decode([CarInfo].self, from: data),
            let selectedCar = cars.first(where: {
                $0.id.uuidString == selectedCarId
            })
        else {
            return .orange
        }

        switch selectedCar.fuelType {

        case .benzina:
            return .orange

        case .diesel:
            return .indigo

        case .gpl:
            return .green
            
        case .metano:
            return .blue

        }
    }
}
