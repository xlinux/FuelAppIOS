import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme.colorScheme)
        }
        .modelContainer(for: [FuelEntry.self, AppSettings.self])
    }
}
