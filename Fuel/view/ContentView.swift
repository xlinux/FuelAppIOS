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
                                .foregroundStyle(.secondary)

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
                                        .foregroundStyle(.secondary)
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

struct StationsMapView: View {

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""
    @AppStorage("stationSearchRadiusMeters") private var stationSearchRadiusMeters: Double = 5000

    @State private var cars: [CarInfo] = []
    @State private var currentLocation: CLLocation?
    @State private var gasStations: [GasStation] = []
    @State private var selectedStation: GasStation?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private let locationService = LocationService()

    private var selectedCar: CarInfo? {
        cars.first { $0.id.uuidString == selectedCarId }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    if let currentLocation {
                        Marker(
                            "Tu",
                            systemImage: "location.fill",
                            coordinate: currentLocation.coordinate
                        )
                        .tint(.blue)
                    }

                    ForEach(gasStations) { station in
                        Annotation(station.name, coordinate: station.coordinate) {
                            Button {
                                selectedStation = station
                                moveMap(to: station, meters: 800)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(station.name)
                                        .font(.caption2.bold())
                                        .lineLimit(1)

                                    if let price = station.price {
                                        Text(String(format: "%.3f €/L", price))
                                            .font(.caption2)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Ricerca distributori...")
                                .font(.caption)
                        }
                        .padding(10)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let selectedStation {
                        selectedStationCard(selectedStation)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("Mappa distributori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadStations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                loadCars()
                await loadStations()
            }
            .onChange(of: selectedCarId) {
                Task {
                    loadCars()
                    await loadStations()
                }
            }
        }
    }

    private func selectedStationCard(_ station: GasStation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(station.name)
                    .font(.headline)

                Spacer()

                if let price = station.price {
                    Text(String(format: "%.3f €/L", price))
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }

            if let address = station.address {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(Int(station.distanceMeters)) metri")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let updated = station.priceUpdatedAtFormatted {
                    Text("\(station.priceFreshnessDot) \(updated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func loadCars() {
        guard
            let data = carsJson.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([CarInfo].self, from: data)
        else {
            cars = []
            return
        }

        cars = decoded
    }

    private func loadStations() async {
        isLoading = true
        errorMessage = nil

        let location = await locationService.requestLocation()
        currentLocation = location

        guard let location else {
            gasStations = []
            selectedStation = nil
            errorMessage = "Posizione non disponibile."
            isLoading = false
            return
        }

        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: stationSearchRadiusMeters * 2,
                longitudinalMeters: stationSearchRadiusMeters * 2
            )
        )

        do {
            let fuelType = selectedCar?.fuelTypeRaw.uppercased() ?? "BENZINA"

            let stations = try await FuelStationAPI.shared.nearbyStations(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                fuelType: fuelType,
                radiusMeters: Int(stationSearchRadiusMeters)
            )

            gasStations = stations.map { station in
                GasStation(
                    name: station.brand ?? station.name ?? "Distributore",
                    address: station.address,
                    coordinate: CLLocationCoordinate2D(
                        latitude: station.latitude,
                        longitude: station.longitude
                    ),
                    distanceMeters: station.distanceMeters,
                    price: station.price,
                    selfService: station.selfService,
                    priceUpdatedAt: station.priceUpdatedAt
                )
            }

            selectedStation = gasStations.first

        } catch {
            gasStations = []
            selectedStation = nil
            errorMessage = "Non riesco a caricare i distributori."
            print("MAP STATIONS ERROR:", error.localizedDescription)
        }

        isLoading = false
    }

    private func moveMap(to station: GasStation, meters: CLLocationDistance) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: station.coordinate,
                latitudinalMeters: meters,
                longitudinalMeters: meters
            )
        )
    }
}
