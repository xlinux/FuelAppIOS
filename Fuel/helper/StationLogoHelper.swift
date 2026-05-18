import SwiftUI

enum StationLogoHelper {

    static func imageName(for brand: String) -> String? {

        let normalized = brand.lowercased()

        if normalized.contains("eni") || normalized.contains("agip") {
            return "logo_eni"
        }

        if normalized.contains("q8") {
            return "logo_q8"
        }

        if normalized.contains("ip") || normalized.contains("api") {
            return "logo_ip"
        }

        if normalized.contains("esso") {
            return "logo_esso"
        }

        if normalized.contains("tamoil") {
            return "logo_tamoil"
        }

        if normalized.contains("erg") {
            return "logo_erg"
        }

        if normalized.contains("enerpetroli") {
            return "logo_enerpetroli"
        }

        if normalized.contains("smaf") {
            return "logo_smaf"
        }

        return nil
    }
}
