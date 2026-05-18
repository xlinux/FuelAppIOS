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
    @State private var visibleStationIds: Set<UUID> = []

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

    private var displayedRecommendedStations: [GasStation] {
        displayStations(from: recommendedStations)
    }

    private var displayedFilteredStations: [GasStation] {
        displayStations(from: filteredGasStations)
    }

    private var currentVisibleListSource: [GasStation] {
        selectedStationsTab == 0 ? displayedRecommendedStations : displayedFilteredStations
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                persistentMapPanel
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Theme.background)

                Form {
                Section {
                    if cars.isEmpty {
                        Text("Nessuna auto salvata. Aggiungila dalle Impostazioni.")
                            .foregroundStyle(.black.opacity(0.7))
                    } else {
                        Picker("Auto", selection: $selectedEntryCarId) {
                            ForEach(cars) { car in
                                Text("\(car.name) - \(car.fuelTypeRaw)")
                                    .tag(car.id.uuidString)
                            }
                        }
                    }
                } header: {
                    Text("Auto")
                        .foregroundStyle(Theme.text)
                }

                Section {
                    TextField("Importo speso", text: $amount)
                        .keyboardType(.decimalPad)

                    TextField("Chilometri odometro", text: $odometerKm)
                        .keyboardType(.decimalPad)

                    if gpsTrackingEnabled {
                        Text("Km stimati da GPS: \(Int(estimatedKmSinceLastRefuel)) km")
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                } header: {
                    Text("Dati rifornimento")
                        .foregroundStyle(Theme.text)
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
                            .foregroundStyle(Theme.accent)
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
                                .foregroundStyle(.black.opacity(0.7))
                        }

                        if recommendedStations.isEmpty {
                            Text("Nessun consiglio calcolato.")
                                .font(.caption)
                                .foregroundStyle(.black.opacity(0.7))
                        } else {
                            ForEach(Array(recommendedStations.enumerated()), id: \.element.id) { index, station in
                                if shouldDisplayStation(at: index, in: recommendedStations) {
                                    stationRow(
                                        station,
                                        pairedStation: pairedStation(at: index, in: recommendedStations)
                                    )
                                }
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
                                    .foregroundStyle(.black.opacity(0.7))
                            }
                            .padding(.vertical, 8)

                        } else if filteredGasStations.isEmpty {
                            Text(
                                nearbyStationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Nessun benzinaio trovato vicino."
                                : "Nessun distributore trovato con questa ricerca."
                            )
                            .foregroundStyle(.black.opacity(0.7))
                        } else {
                            ForEach(Array(filteredGasStations.enumerated()), id: \.element.id) { index, station in
                                if shouldDisplayStation(at: index, in: filteredGasStations) {
                                    stationRow(
                                        station,
                                        pairedStation: pairedStation(at: index, in: filteredGasStations)
                                    )
                                }
                            }
                        }
                    }
                } header: {
                    Text("Distributori")
                        .foregroundStyle(Theme.text)
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Theme.background)
            .background(Theme.background)
            .foregroundStyle(.black)
            .navigationTitle("Nuovo rifornimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                    visibleStationIds = []
                    await loadLocationAndStations()
                }
            }
            .onChange(of: selectedStationsTab) {
                visibleStationIds = []
            }
            .onChange(of: nearbyStationSearchText) {
                visibleStationIds = []
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
    }

    @ViewBuilder
    private var persistentMapPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mappa")
                .font(.headline)
                .foregroundStyle(Theme.text)

            if let location = currentLocation {
                Map(position: $cameraPosition) {
                    Marker("Tu", coordinate: location.coordinate)

                    ForEach(gasStations) { station in
                        Annotation(station.name, coordinate: station.coordinate) {
                            Button {
                                selectStation(station)
                            } label: {
                                HStack(spacing: 8) {
                                    if let logoName = StationLogoHelper.imageName(for: station.name) {
                                        Image(logoName)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 32, height: 32)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "fuelpump.fill")
                                            .font(.title3)
                                            .foregroundStyle(Theme.accent)
                                            .frame(width: 32, height: 32)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(station.name)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                            .foregroundStyle(.black)

                                        if let price = station.price {
                                            Text("\(selectedEntryCar?.fuelTypeRaw ?? "Carburante") \(String(format: "%.3f €/L", price))")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        } else {
                                            Text("Prezzo non disponibile")
                                                .font(.caption2)
                                                .foregroundStyle(.gray)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let currentAddress {
                    Text(currentAddress)
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.7))
                        .padding(.horizontal, 6)
                }
            } else {
                Text("Posizione non disponibile")
                    .foregroundStyle(.black.opacity(0.7))

                Button("Rileva posizione") {
                    Task {
                        await loadLocationAndStations()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: GasStation, pairedStation: GasStation?) -> some View {
        let prices = mergedPrices(primary: station, secondary: pairedStation)

        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        if let logoName = StationLogoHelper.imageName(for: station.name) {
                            Image(logoName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: "fuelpump.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, height: 28)
                        }

                        Text(station.name)
                            .font(.headline)
                            .foregroundStyle(.black)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if let selfPrice = prices.selfPrice {
                            Text("Self \(String(format: "%.3f €/L", selfPrice))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }

                        if let servedPrice = prices.servedPrice {
                            Text("Servito \(String(format: "%.3f €/L", servedPrice))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        if prices.selfPrice == nil && prices.servedPrice == nil {
                            Text("Prezzo non disponibile")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                }

                if let address = station.address {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                HStack(spacing: 10) {
                    Text("\(Int(station.distanceMeters)) metri")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    if let updated = station.priceUpdatedAtFormatted {
                        Text("\(station.priceFreshnessDot) \(updated)")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            Button {
                stationForActions = station
            } label: {
                Image(systemName: "map")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectStation(station)
        }
        .onAppear {
            updateVisibleStation(station, isVisible: true)
        }
        .onDisappear {
            updateVisibleStation(station, isVisible: false)
        }
    }

    private func stationKey(_ station: GasStation) -> String {
        let address = (station.address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return "\(station.name.lowercased())|\(address)"
    }

    private func shouldDisplayStation(at index: Int, in stations: [GasStation]) -> Bool {
        guard index > 0 else { return true }
        return stationKey(stations[index]) != stationKey(stations[index - 1])
    }

    private func pairedStation(at index: Int, in stations: [GasStation]) -> GasStation? {
        let nextIndex = index + 1
        guard nextIndex < stations.count else { return nil }
        guard stationKey(stations[index]) == stationKey(stations[nextIndex]) else { return nil }
        return stations[nextIndex]
    }

    private func mergedPrices(primary: GasStation, secondary: GasStation?) -> (selfPrice: Double?, servedPrice: Double?) {
        var selfPrice: Double?
        var servedPrice: Double?

        if primary.selfService == true {
            selfPrice = primary.price
        } else if primary.selfService == false {
            servedPrice = primary.price
        } else {
            selfPrice = primary.price
        }

        if let secondary {
            if secondary.selfService == true {
                selfPrice = secondary.price ?? selfPrice
            } else if secondary.selfService == false {
                servedPrice = secondary.price ?? servedPrice
            }
        }

        return (selfPrice, servedPrice)
    }

    private func displayStations(from stations: [GasStation]) -> [GasStation] {
        stations.enumerated().compactMap { index, station in
            shouldDisplayStation(at: index, in: stations) ? station : nil
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
        visibleStationIds = []

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

    private func updateVisibleStation(_ station: GasStation, isVisible: Bool) {
        if isVisible {
            visibleStationIds.insert(station.id)
        } else {
            visibleStationIds.remove(station.id)
        }

        guard let firstVisible = currentVisibleListSource.first(where: {
            visibleStationIds.contains($0.id)
        }) else {
            return
        }

        if selectedStation?.id != firstVisible.id {
            selectedStation = firstVisible
            moveMap(to: firstVisible, meters: 800)
        }
    }

    private func openInAppleMaps(_ station: GasStation) {
        let location = CLLocation(
            latitude: station.coordinate.latitude,
            longitude: station.coordinate.longitude
        )
        let mapItem = MKMapItem(location: location, address: nil)
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
