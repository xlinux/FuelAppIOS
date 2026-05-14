import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {

    @Query(sort: \FuelEntry.date, order: .forward)
    private var entries: [FuelEntry]

    private var totalSpent: Double {
        entries.reduce(0) { $0 + $1.amount }
    }

    private var totalKm: Double {
        guard let first = entries.first?.odometerKm,
              let last = entries.last?.odometerKm,
              last > first else {
            return 0
        }
        return last - first
    }

    private var costPerKm: Double {
        guard totalKm > 0 else { return 0 }
        return totalSpent / totalKm
    }

    private var kmPerEuro: Double {
        guard totalSpent > 0 else { return 0 }
        return totalKm / totalSpent
    }

    private var averageRefuel: Double {
        guard !entries.isEmpty else { return 0 }
        return totalSpent / Double(entries.count)
    }

    private var lastEntry: FuelEntry? {
        entries.last
    }

    private var previousEntry: FuelEntry? {
        guard entries.count >= 2 else { return nil }
        return entries[entries.count - 2]
    }

    private var kmSinceLastRefuel: Double {
        guard let previousEntry, let lastEntry else { return 0 }
        return max(0, lastEntry.odometerKm - previousEntry.odometerKm)
    }

    private var lastRefuelEstimatedKm: Double {
        guard let lastEntry else { return 0 }
        return lastEntry.amount * kmPerEuro
    }

    private var estimatedRemainingKm: Double {
        max(0, lastRefuelEstimatedKm - kmSinceLastRefuel)
    }

    private var fuelStatusText: String {
        guard entries.count >= 3 else {
            return "Servono almeno 3 rifornimenti per stimare meglio l’autonomia."
        }

        if estimatedRemainingKm <= 20 {
            return "Probabilmente dovresti fare benzina a breve."
        } else if estimatedRemainingKm <= 60 {
            return "Carburante stimato basso."
        } else {
            return "Autonomia stimata ancora buona."
        }
    }

    private var fuelStatusIcon: String {
        if estimatedRemainingKm <= 20 {
            return "exclamationmark.triangle.fill"
        } else if estimatedRemainingKm <= 60 {
            return "fuelpump.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var daysSinceLastRefuel: Int {
        guard let lastDate = entries.last?.date else { return 0 }

        return Calendar.current.dateComponents(
            [.day],
            from: lastDate,
            to: Date()
        ).day ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Stima carburante") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: fuelStatusIcon)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(fuelStatusText)
                                .font(.headline)

                            Text("Residuo stimato: \(Int(estimatedRemainingKm)) km")
                                .foregroundStyle(.secondary)
                        }
                    }

                    statRow("Km stimati con ultimo rifornimento", "\(Int(lastRefuelEstimatedKm)) km")
                    statRow("Km percorsi dall’ultimo", "\(Int(kmSinceLastRefuel)) km")
                    statRow("Km residui stimati", "\(Int(estimatedRemainingKm)) km")
                    statRow("Media km per euro", String(format: "%.2f km/€", kmPerEuro))
                }

                Section("Dall’ultimo rifornimento") {
                    statRow("Giorni passati", "\(daysSinceLastRefuel)")
                    statRow("Ultima spesa", lastEntry?.amount.formatted(.currency(code: "EUR")) ?? "-")
                    statRow("Ultimo chilometraggio", lastEntry == nil ? "-" : "\(Int(lastEntry!.odometerKm)) km")
                }

                Section("Statistiche generali") {
                    statRow("Totale speso", totalSpent.formatted(.currency(code: "EUR")))
                    statRow("Km totali tracciati", "\(Int(totalKm)) km")
                    statRow("Costo medio/km", costPerKm.formatted(.currency(code: "EUR")))
                    statRow("Media rifornimento", averageRefuel.formatted(.currency(code: "EUR")))
                    statRow("Numero rifornimenti", "\(entries.count)")
                }

                Section("Spesa per rifornimento") {
                    if entries.isEmpty {
                        Text("Nessun dato disponibile")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(entries) { entry in
                            BarMark(
                                x: .value("Data", entry.date, unit: .day),
                                y: .value("Spesa", entry.amount)
                            )
                        }
                        .frame(height: 220)
                    }
                }

                Section("Andamento chilometri") {
                    if entries.isEmpty {
                        Text("Nessun dato disponibile")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(entries) { entry in
                            LineMark(
                                x: .value("Data", entry.date, unit: .day),
                                y: .value("Km", entry.odometerKm)
                            )
                        }
                        .frame(height: 220)
                    }
                }
            }
            .navigationTitle("Dashboard")
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}
