import AppIntents

struct FuelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegisterFuelIntent(),
            phrases: [
                "Registra benzina con \(.applicationName)",
                "Salva rifornimento con \(.applicationName)",
                "Aggiungi rifornimento con \(.applicationName)"
            ],
            shortTitle: "Registra benzina",
            systemImageName: "fuelpump.fill"
        )
    }
}
