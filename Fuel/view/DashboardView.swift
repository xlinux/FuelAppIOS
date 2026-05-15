import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {

    @Query(sort: \FuelEntry.date, order: .forward)
    private var entries: [FuelEntry]

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    @Environment(\.modelContext) private var modelContext

    @State private var isLoadingRemoteEntries = false

    private var selectedCar: CarInfo? {
        guard
            let data = carsJson.data(using: .utf8),
            let cars = try? JSONDecoder().decode([CarInfo].self, from: data)
        else {
            return nil
        }

        return cars.first { $0.id.uuidString == selectedCarId }
    }

    private var carEntries: [FuelEntry] {
        guard let selectedCar else {
            return entries
        }

        return entries.filter { entry in
            entry.carName == selectedCar.name
        }
    }

    private var totalSpent: Double {
        carEntries.reduce(0) { $0 + $1.amount }
    }

    private var totalKm: Double {
        guard let first = carEntries.first?.odometerKm,
              let last = carEntries.last?.odometerKm,
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
        guard !carEntries.isEmpty else { return 0 }
        return totalSpent / Double(carEntries.count)
    }

    private var lastEntry: FuelEntry? {
        carEntries.last
    }

    private var previousEntry: FuelEntry? {
        guard carEntries.count >= 2 else { return nil }
        return carEntries[carEntries.count - 2]
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
        guard carEntries.count >= 3 else {
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
        guard let lastDate = carEntries.last?.date else { return 0 }

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
                    if let selectedCar {
                        statRow("Statistiche auto", selectedCar.name)
                    }
                    if isLoadingRemoteEntries {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Aggiornamento dati...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    statRow("Totale speso", totalSpent.formatted(.currency(code: "EUR")))
                    statRow("Km totali tracciati", "\(Int(totalKm)) km")
                    statRow("Costo medio/km", costPerKm.formatted(.currency(code: "EUR")))
                    statRow("Media rifornimento", averageRefuel.formatted(.currency(code: "EUR")))
                    statRow("Numero rifornimenti", "\(carEntries.count)")
                }

                Section("Spesa per rifornimento") {
                    if carEntries.isEmpty {
                        Text("Nessun dato disponibile")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(carEntries) { entry in
                            BarMark(
                                x: .value("Data", entry.date, unit: .day),
                                y: .value("Spesa", entry.amount)
                            )
                        }
                        .frame(height: 220)
                    }
                }

                Section("Andamento chilometri") {
                    if carEntries.isEmpty {
                        Text("Nessun dato disponibile")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(carEntries) { entry in
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
            .task {
                await syncFuelEntriesFromBackend()
            }
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

    private func syncFuelEntriesFromBackend() async {
        await MainActor.run {
            isLoadingRemoteEntries = true
        }

        do {
            let remoteEntries = try await UserDataAPI.shared.fetchFuelEntries()

            await MainActor.run {
                for entry in entries {
                    modelContext.delete(entry)
                }

                for remote in remoteEntries {
                    let entry = FuelEntry(
                        date: parseRemoteDate(remote.entryDate) ?? .now,
                        amount: remote.amount,
                        odometerKm: remote.odometerKm,
                        latitude: remote.latitude,
                        longitude: remote.longitude,
                        address: remote.address,
                        stationName: remote.stationName,
                        carName: remote.carName,
                        fuelTypeRaw: remote.fuelType,
                        gpsEstimatedKm: remote.gpsEstimatedKm,
                        fuelPrice: remote.fuelPrice
                    )

                    modelContext.insert(entry)
                }

                do {
                    try modelContext.save()
                } catch {
                    print("ERRORE SAVE SYNC DASHBOARD:", error.localizedDescription)
                }

                isLoadingRemoteEntries = false
            }

        } catch {
            print("ERRORE SYNC DASHBOARD BACKEND:", error.localizedDescription)

            await MainActor.run {
                isLoadingRemoteEntries = false
            }
        }
    }

    private func parseRemoteDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()

        if let date = isoFormatter.date(from: value) {
            return date
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "it_IT")
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        return fallbackFormatter.date(from: value)
    }
}
