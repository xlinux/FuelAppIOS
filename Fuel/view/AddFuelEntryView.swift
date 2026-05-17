import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UIKit

struct GasStation: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let price: Double?
    let selfService: Bool?
    let priceUpdatedAt: String?

    static func == (lhs: GasStation, rhs: GasStation) -> Bool {
        lhs.id == rhs.id
    }

    var priceUpdatedAtFormatted: String? {
        guard let priceUpdatedAt else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()

        if let date = isoFormatter.date(from: priceUpdatedAt) {
            let output = DateFormatter()
            output.locale = Locale(identifier: "it_IT")
            output.dateStyle = .short
            output.timeStyle = .short
            return output.string(from: date)
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "it_IT")
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        if let date = fallbackFormatter.date(from: priceUpdatedAt) {
            let output = DateFormatter()
            output.locale = Locale(identifier: "it_IT")
            output.dateStyle = .short
            output.timeStyle = .short
            return output.string(from: date)
        }

        return priceUpdatedAt
    }

    var priceAgeDays: Int? {
        guard let priceUpdatedAt else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        var parsedDate = isoFormatter.date(from: priceUpdatedAt)

        if parsedDate == nil {
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.locale = Locale(identifier: "it_IT")
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            parsedDate = fallbackFormatter.date(from: priceUpdatedAt)
        }

        guard let parsedDate else {
            return nil
        }

        return Calendar.current.dateComponents(
            [.day],
            from: parsedDate,
            to: Date()
        ).day
    }

    var priceFreshnessDot: String {
        guard let priceAgeDays else {
            return "⚪️"
        }

        if priceAgeDays <= 2 {
            return "🟢"
        } else if priceAgeDays <= 7 {
            return "🟡"
        } else {
            return "🔴"
        }
    }
}

struct AddFuelEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    @AppStorage("gpsTrackingEnabled") private var gpsTrackingEnabled: Bool = false
    @AppStorage("estimatedKmSinceLastRefuel") private var estimatedKmSinceLastRefuel: Double = 0
    @AppStorage("stationSearchRadiusMeters") private var stationSearchRadiusMeters: Double = 5000

    @State private var cars: [CarInfo] = []
    @State private var selectedEntryCarId = ""

    @State private var amount = ""
    @State private var odometerKm = ""
    @State private var isSaving = false

    @State private var currentLocation: CLLocation?
    @State private var currentAddress: String?

    @State private var gasStations: [GasStation] = []
    @State private var selectedStation: GasStation?

    @State private var isLoadingStations = false
    @State private var isLoadingBestStation = false
    @State private var bestStationMessage: String?
    @State private var recommendedStations: [GasStation] = []
    @State private var selectedStationsTab = 0
    @State private var nearbyStationSearchText = ""

    @State private var stationForActions: GasStation?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private let locationService = LocationService()

    private var selectedEntryCar: CarInfo? {
        cars.first { $0.id.uuidString == selectedEntryCarId }
    }

    private var filteredGasStations: [GasStation] {
        let searchText = nearbyStationSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !searchText.isEmpty else {
            return gasStations
        }

        return gasStations.filter { station in
            station.name.localizedCaseInsensitiveContains(searchText)
            || (station.address?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Auto") {
                    if cars.isEmpty {
                        Text("Nessuna auto salvata. Aggiungila dalle Impostazioni.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Auto", selection: $selectedEntryCarId) {
                            ForEach(cars) { car in
                                Text("\(car.name) - \(car.fuelTypeRaw)")
                                    .tag(car.id.uuidString)
                            }
                        }
                    }
                }

                Section("Dati rifornimento") {
                    TextField("Importo speso", text: $amount)
                        .keyboardType(.decimalPad)

                    TextField("Chilometri odometro", text: $odometerKm)
                        .keyboardType(.decimalPad)

                    if gpsTrackingEnabled {
                        Text("Km stimati da GPS: \(Int(estimatedKmSinceLastRefuel)) km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Mappa") {
                    if let location = currentLocation {
                        Map(position: $cameraPosition) {
                            Marker("Tu", coordinate: location.coordinate)

                            ForEach(gasStations) { station in
                                Annotation(station.name, coordinate: station.coordinate) {
                                    Button {
                                        selectStation(station)
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
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let currentAddress {
                            Text(currentAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Posizione non disponibile")
                            .foregroundStyle(.secondary)

                        Button("Rileva posizione") {
                            Task {
                                await loadLocationAndStations()
                            }
                        }
                    }
                }

                Section {

                    Button {
                        Task {
                            if selectedStationsTab == 0 {
                                await loadBestStations()
                            } else {
                                await loadLocationAndStations()
                            }
                        }
                    } label: {
                        HStack {

                            if selectedStationsTab == 0, isLoadingBestStation {
                                ProgressView()
                            }

                            if selectedStationsTab == 1, isLoadingStations {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }

                            Text(
                                selectedStationsTab == 0
                                ? "Trova i 2 migliori distributori"
                                : "Aggiorna distributori nel raggio"
                            )
                        }
                    }
                    .disabled(
                        selectedStationsTab == 0
                        ? (currentLocation == nil || isLoadingBestStation)
                        : isLoadingStations
                    )

                    Picker("Lista distributori", selection: $selectedStationsTab) {
                        Text("Consigliati")
                            .tag(0)

                        Text("Nel raggio")
                            .tag(1)
                    }
                    .pickerStyle(.segmented)

                    if selectedStationsTab == 0 {

                        if let bestStationMessage {
                            Text(bestStationMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if recommendedStations.isEmpty {
                            Text("Nessun consiglio calcolato.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(recommendedStations) { station in
                                stationRow(station)
                            }
                        }

                    } else {
                        TextField("Cerca distributore", text: $nearbyStationSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if isLoadingStations {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(.circular)

                                Text("Ricerca distributori...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)

                        } else if filteredGasStations.isEmpty {
                            Text(
                                nearbyStationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Nessun benzinaio trovato vicino."
                                : "Nessun distributore trovato con questa ricerca."
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredGasStations) { station in
                                stationRow(station)
                            }
                        }
                    }
                } header: {
                    Text("Distributori")
                }
            }
            .navigationTitle("Nuovo rifornimento")
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Salva")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                loadCars()
                selectedEntryCarId = selectedCarId

                if selectedEntryCarId.isEmpty, let first = cars.first {
                    selectedEntryCarId = first.id.uuidString
                }

                await loadLocationAndStations()
            }
            .onChange(of: selectedEntryCarId) {
                Task {
                    bestStationMessage = nil
                    recommendedStations = []
                    await loadLocationAndStations()
                }
            }
            .confirmationDialog(
                "Apri navigazione",
                isPresented: Binding(
                    get: { stationForActions != nil },
                    set: { if !$0 { stationForActions = nil } }
                )
            ) {
                if let station = stationForActions {
                    Button("Apri in Apple Maps") {
                        openInAppleMaps(station)
                        stationForActions = nil
                    }

                    Button("Apri in Google Maps") {
                        openInGoogleMaps(station)
                        stationForActions = nil
                    }
                }

                Button("Annulla", role: .cancel) {
                    stationForActions = nil
                }
            } message: {
                Text(stationForActions?.name ?? "Distributore")
            }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: GasStation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.headline)

                if let address = station.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(station.distanceMeters)) metri")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let price = station.price {
                    Text(String(format: "%.3f €/L", price))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updated = station.priceUpdatedAtFormatted {
                    Text("\(station.priceFreshnessDot) Aggiornato: \(updated)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let selfService = station.selfService {
                    Text(selfService ? "Self" : "Servito")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("Tocca per selezionare, tieni premuto per navigare")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if selectedStation?.id == station.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "map")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectStation(station)
        }
        .onLongPressGesture {
            stationForActions = station
        }
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

    private func loadLocationAndStations() async {
        isLoadingStations = true
        gasStations = []
        selectedStation = nil

        let location = await locationService.requestLocation()
        currentLocation = location

        if let location {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1500,
                    longitudinalMeters: 1500
                )
            )
        }

        guard let location else {
            isLoadingStations = false
            return
        }

        currentAddress = await locationService.reverseGeocode(location)
        gasStations = await findNearbyGasStations(from: location)
        selectedStation = gasStations.first

        if let selectedStation {
            moveMap(to: selectedStation, meters: 1000)
        }

        isLoadingStations = false
    }

    private func findNearbyGasStations(from location: CLLocation) async -> [GasStation] {
        do {
            let fuelType = selectedEntryCar?.fuelTypeRaw.uppercased() ?? "BENZINA"

            let stations = try await FuelStationAPI.shared.nearbyStations(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                fuelType: fuelType,
                radiusMeters: Int(stationSearchRadiusMeters)
            )

            return stations.map { station in
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
        } catch {
            print("BACKEND STATIONS ERROR:", error.localizedDescription)
            return []
        }
    }

    private func loadBestStations() async {
        guard let location = currentLocation else {
            return
        }

        isLoadingBestStation = true
        bestStationMessage = nil
        recommendedStations = []

        do {
            let fuelType = selectedEntryCar?.fuelTypeRaw.uppercased() ?? "BENZINA"

            let bestStations = try await FuelStationAPI.shared.bestStations(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                fuelType: fuelType,
                liters: 30,
                carKmPerLiter: 15,
                radiusMeters: Int(stationSearchRadiusMeters),
                limit: 10
            )

            recommendedStations = Array(
                bestStations
                    .map { station in
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
                    .filter { $0.priceFreshnessDot == "🟢" }
                    .prefix(2)
            )

            if recommendedStations.isEmpty {
                bestStationMessage = "Nessun distributore consigliato con prezzo aggiornato di recente."
            }

            for station in recommendedStations {
                if !gasStations.contains(where: { $0.address == station.address && $0.name == station.name }) {
                    gasStations.insert(station, at: 0)
                }
            }

            if let first = recommendedStations.first {
                selectStation(first)
            }

        } catch {
            print("BEST STATIONS ERROR:", error.localizedDescription)
            bestStationMessage = "Non riesco a calcolare i distributori consigliati."
        }

        isLoadingBestStation = false
    }

    private func selectStation(_ station: GasStation) {
        selectedStation = station
        moveMap(to: station, meters: 800)
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

    private func openInAppleMaps(_ station: GasStation) {
        let placemark = MKPlacemark(coordinate: station.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = station.name

        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openInGoogleMaps(_ station: GasStation) {
        let lat = station.coordinate.latitude
        let lng = station.coordinate.longitude

        if let url = URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        if let webUrl = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)") {
            UIApplication.shared.open(webUrl)
        }
    }

    private func save() async {
        guard
            let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")),
            let kmValue = Double(odometerKm.replacingOccurrences(of: ",", with: "."))
        else {
            return
        }

        isSaving = true

        if currentLocation == nil {
            await loadLocationAndStations()
        }

        let selectedCar = selectedEntryCar

        let entry = FuelEntry(
            amount: amountValue,
            odometerKm: kmValue,
            latitude: selectedStation?.coordinate.latitude ?? currentLocation?.coordinate.latitude,
            longitude: selectedStation?.coordinate.longitude ?? currentLocation?.coordinate.longitude,
            address: selectedStation?.address ?? currentAddress,
            stationName: selectedStation?.name,
            carName: selectedCar?.name,
            fuelTypeRaw: selectedCar?.fuelTypeRaw,
            gpsEstimatedKm: gpsTrackingEnabled ? estimatedKmSinceLastRefuel : nil,
            fuelPrice: selectedStation?.price
        )

        modelContext.insert(entry)

        do {
            try modelContext.save()
        } catch {
            print("ERRORE SALVATAGGIO LOCALE RIFORNIMENTO:", error.localizedDescription)
        }

        let remoteRequest = RemoteFuelEntryRequest(
            carId: selectedCar?.id.uuidString,
            carName: selectedCar?.name,
            fuelType: selectedCar?.fuelTypeRaw.uppercased(),
            amount: amountValue,
            odometerKm: kmValue,
            fuelPrice: selectedStation?.price,
            gpsEstimatedKm: gpsTrackingEnabled ? estimatedKmSinceLastRefuel : nil,
            latitude: selectedStation?.coordinate.latitude ?? currentLocation?.coordinate.latitude,
            longitude: selectedStation?.coordinate.longitude ?? currentLocation?.coordinate.longitude,
            address: selectedStation?.address ?? currentAddress,
            stationName: selectedStation?.name,
            entryDate: ISO8601DateFormatter().string(from: Date())
        )

        do {
            _ = try await UserDataAPI.shared.createFuelEntry(remoteRequest)
            print("RIFORNIMENTO SALVATO SU BACKEND")
        } catch {
            print("ERRORE SALVATAGGIO BACKEND RIFORNIMENTO:", error.localizedDescription)
        }

        if gpsTrackingEnabled {
            estimatedKmSinceLastRefuel = 0
        }

        isSaving = false
        dismiss()
    }
}
