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
    @State private var selectedRange: SpendingRange = .weekly
    @State private var customStartDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var customEndDate: Date = Calendar.current.startOfDay(for: .now)

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    private var filteredEntries: [FuelEntry] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday

        switch selectedRange {
        case .weekly:
            guard
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: .now),
                let endOfWeek = calendar.date(byAdding: .second, value: -1, to: weekInterval.end)
            else {
                return entries
            }
            return entries.filter { $0.date >= weekInterval.start && $0.date <= endOfWeek }
        case .monthly:
            guard
                let monthInterval = calendar.dateInterval(of: .month, for: .now),
                let endOfMonth = calendar.date(byAdding: .second, value: -1, to: monthInterval.end)
            else {
                return entries
            }
            return entries.filter { $0.date >= monthInterval.start && $0.date <= endOfMonth }
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStartDate, customEndDate))) else {
                return entries
            }
            return entries.filter { $0.date >= start && $0.date < end }
        case .all:
            return entries
        }
    }

    private var totalSpent: Double {
        filteredEntries.reduce(0) { $0 + $1.amount }
    }

    private var appTintColor: Color {

        Theme.accent

    }

    private enum SpendingRange: String, CaseIterable, Identifiable {
        case weekly
        case monthly
        case custom
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekly:
                return "Settimanale"
            case .monthly:
                return "Mensile"
            case .custom:
                return "Personalizzato"
            case .all:
                return "Totale"
            }
        }
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

                        VStack(alignment: .leading, spacing: 8) {

                            Text("Totale speso")
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.7))

                            Picker("Periodo", selection: $selectedRange) {
                                ForEach(SpendingRange.allCases) { range in
                                    Text(range.title).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)

                            if selectedRange == .custom {
                                HStack(spacing: 12) {
                                    DatePicker(
                                        "Da",
                                        selection: $customStartDate,
                                        displayedComponents: .date
                                    )
                                    DatePicker(
                                        "A",
                                        selection: $customEndDate,
                                        displayedComponents: .date
                                    )
                                }
                                .datePickerStyle(.compact)
                                .font(.caption)
                                .labelsHidden()
                            }

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

                    Section {

                        if filteredEntries.isEmpty {
                            Text("Nessun rifornimento effettuato")
                                .font(.subheadline)
                                .foregroundStyle(.black.opacity(0.7))
                        } else {
                            ForEach(filteredEntries) { entry in

                                NavigationLink {
                                    FuelEntryDetailView(entry: entry)
                                } label: {
                                    fuelEntryRow(for: entry)
                                }
                            }
                            .onDelete(perform: deleteEntries)
                        }
                    } header: {
                        Text("Elenco Rifornimenti")
                            .foregroundStyle(.white)
                    }
                    .scrollContentBackground(.hidden)
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
                    "Elenco Rifornimenti",
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
            let entry = filteredEntries[index]
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

    @ViewBuilder
    private func fuelEntryRow(for entry: FuelEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    entry.amount,
                    format: .currency(code: "EUR")
                )
                .font(.headline)

                Spacer()

                Text("\(Int(entry.odometerKm)) km")
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

            Text(formattedItalianDate(entry.date))
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

    private func formattedItalianDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMMM yyyy"

        let rawDate = formatter.string(from: date)
        var parts = rawDate.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)

        if parts.count >= 2 {
            parts[1] = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        }

        return parts.joined(separator: " ")
    }
}
