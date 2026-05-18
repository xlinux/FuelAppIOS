import SwiftUI
import SwiftData
import CoreLocation
import MapKit


struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FuelEntry.date, order: .reverse)
    private var entries: [FuelEntry]

    @State private var showingAdd = false
    @State private var isLoadingRemoteEntries = false

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    private var totalSpent: Double {
        entries.reduce(0) { $0 + $1.amount }
    }

    private var appTintColor: Color {

        Theme.accent

    }

    var body: some View {

        TabView {

            HomeView()
                .tabItem {
                    Label(
                        "Home",
                        systemImage: "house.fill"
                    )
                }

            StationsMapView()
                .tabItem {
                    Label(
                        "Mappa",
                        systemImage: "map.fill"
                    )
                }

            NavigationStack {

                List {

                    Section {

                        VStack(alignment: .leading) {

                            Text("Totale speso")
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.7))

                            Text(
                                totalSpent,
                                format: .currency(code: "EUR")
                            )
                            .font(.largeTitle.bold())

                            if isLoadingRemoteEntries {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Sincronizzazione rifornimenti...")
                                        .font(.caption)
                                        .foregroundStyle(.black.opacity(0.7))
                                }
                            }
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
                                        .foregroundStyle(.black.opacity(0.7))
                                    }

                                    if let carName = entry.carName {
                                        Text(carName)
                                            .font(.caption)
                                            .foregroundStyle(Theme.accent)
                                    }

                                    if let fuelType = entry.fuelTypeRaw {
                                        Text(fuelType)
                                            .font(.caption2)
                                            .foregroundStyle(.black.opacity(0.7))
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
                                            .foregroundStyle(.black.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteEntries)
                    }.scrollContentBackground(.hidden)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .foregroundStyle(.black)
                .navigationTitle("Rifornimenti")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {

                    ToolbarItem(placement: .topBarTrailing) {

                        Button {
                            showingAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .navigationDestination(isPresented: $showingAdd) {
                    AddFuelEntryView()
                }
                .task {
                    await syncFuelEntriesFromBackend()
                }
            }
            .tabItem {
                Label(
                    "Rifornimenti",
                    systemImage: "fuelpump.fill"
                ).background(Theme.card)
                    .foregroundStyle(Theme.text)
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
        .tint(Theme.accent)
        .toolbarColorScheme(.dark, for: .tabBar)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(Theme.background)
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            modelContext.delete(entry)
        }

        do {
            try modelContext.save()
        } catch {
            print("ERRORE DELETE LOCALE RIFORNIMENTO:", error.localizedDescription)
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
                    print("ERRORE SAVE SYNC RIFORNIMENTI:", error.localizedDescription)
                }

                isLoadingRemoteEntries = false
            }

        } catch {
            print("ERRORE SYNC RIFORNIMENTI BACKEND:", error.localizedDescription)

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

