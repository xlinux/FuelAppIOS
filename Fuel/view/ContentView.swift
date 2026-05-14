import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FuelEntry.date, order: .reverse)
    private var entries: [FuelEntry]

    @State private var showingAdd = false

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    private var totalSpent: Double {
        entries.reduce(0) { $0 + $1.amount }
    }

    private var appTintColor: Color {
        guard
            let data = carsJson.data(using: .utf8),
            let cars = try? JSONDecoder().decode([CarInfo].self, from: data),
            let selectedCar = cars.first(where: {
                $0.id.uuidString == selectedCarId
            })
        else {
            return .green
        }

        switch selectedCar.fuelType {
        case .benzina:
            return .orange

        case .diesel:
            return .indigo

        case .elettrico:
            return .green
        }
    }

    var body: some View {

        TabView {

            NavigationStack {

                List {

                    Section {

                        VStack(alignment: .leading) {

                            Text("Totale speso")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(
                                totalSpent,
                                format: .currency(code: "EUR")
                            )
                            .font(.largeTitle.bold())
                        }
                        .padding(.vertical, 8)
                    }

                    Section("Rifornimenti") {

                        ForEach(entries) { entry in

                            NavigationLink {
                                FuelEntryDetailView(entry: entry)
                            } label: {

                                VStack(alignment: .leading, spacing: 4) {

                                    HStack {

                                        Text(
                                            entry.amount,
                                            format: .currency(code: "EUR")
                                        )
                                        .font(.headline)

                                        Spacer()

                                        Text(
                                            "\(entry.odometerKm, specifier: "%.0f") km"
                                        )
                                        .foregroundStyle(.secondary)
                                    }

                                    if let carName = entry.carName {
                                        Text(carName)
                                            .font(.caption)
                                            .foregroundStyle(appTintColor)
                                    }

                                    if let fuelType = entry.fuelTypeRaw {
                                        Text(fuelType)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(entry.date, style: .date)
                                        .font(.caption)

                                    if let stationName = entry.stationName {
                                        Text(stationName)
                                            .font(.caption)
                                    }

                                    if let address = entry.address {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
                .navigationTitle("Rifornimenti")
                .toolbar {

                    ToolbarItem(placement: .topBarTrailing) {

                        Button {
                            showingAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAdd) {
                    AddFuelEntryView()
                }
            }
            .tabItem {
                Label(
                    "Rifornimenti",
                    systemImage: "fuelpump.fill"
                )
            }

            DashboardView()
                .tabItem {
                    Label(
                        "Dashboard",
                        systemImage: "chart.bar.fill"
                    )
                }

            SettingsView()
                .tabItem {
                    Label(
                        "Impostazioni",
                        systemImage: "gearshape.fill"
                    )
                }
        }
        .tint(appTintColor)
    }

    private func deleteEntries(at offsets: IndexSet) {

        for index in offsets {
            modelContext.delete(entries[index])
        }
    }
}
