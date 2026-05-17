import AppIntents

struct FuelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegisterFuelIntent(),
            phrases: [
                "Registra rifornimento con \(.applicationName)",
                "Salva rifornimento con \(.applicationName)",
                "Aggiungi rifornimento con \(.applicationName)"
            ],
            shortTitle: "Registra rifornimento",
            systemImageName: "fuelpump.fill"
        )
    }
}
