import SwiftUI

enum StationLogoHelper {

    static func imageName(for brand: String) -> String? {

        let normalized = brand.lowercased()
        let normalizedWords = normalized
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: " ",
                options: .regularExpression
            )

        if normalized.contains("eni") || normalized.contains("agip") {
            return "logo_eni"
        }

        if normalized.contains("q8")  || normalized.contains("tiber"){
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

        if normalized.contains("sette") {
            return "logo_sette"
        }
        
        if normalized.contains("icm") {
            return "logo_icm"
        }
        
        if normalized.contains("cp") || normalizedWords.split(separator: " ").contains("cp") {
            return "logo_cp"
        }
        
        if normalized.contains("kero") {
            return "logo_keropetrol"
        }
        
        if normalized.contains("shell") {
            return "logo_shell"
        }

        return nil
    }
}
