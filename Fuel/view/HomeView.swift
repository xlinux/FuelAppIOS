import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UIKit

struct HomeView: View {

    @Query(sort: \FuelEntry.date, order: .forward)
    private var entries: [FuelEntry]

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""
    @AppStorage("stationSearchRadiusMeters") private var stationSearchRadiusMeters: Double = 5000

    @State private var cars: [CarInfo] = []
    @State private var recommendedStations: [GasStation] = []
    @State private var isLoadingStations = false
    @State private var stationError: String?
    @State private var stationForActions: GasStation?
    @State private var selectedRecommendedStationId: UUID?
    @State private var selectedFuelType = "BENZINA"
    @State private var showingAdd = false

    private let locationService = LocationService()

    private var selectedCar: CarInfo? {
        cars.first { $0.id.uuidString == selectedCarId }
    }

    private var carEntries: [FuelEntry] {
        guard let selectedCar else {
            return entries
        }

        return entries.filter { entry in
            entry.carName == selectedCar.name
        }
    }

    private var fuelTypeForApi: String {
        selectedFuelType
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

    private var kmPerEuro: Double {
        guard totalSpent > 0 else { return 0 }
        return totalKm / totalSpent
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
            return "Aggiungi almeno 3 rifornimenti per stimare meglio l’autonomia."
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: fuelStatusIcon)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(fuelStatusText)
                                    .font(.headline)

                                Text("Residuo stimato: \(Int(estimatedRemainingKm)) km")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        Button {
                            showingAdd = true
                        } label: {
                            Label("Aggiungi rifornimento", systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    if let selectedCar {
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                            Text(selectedCar.name)
                                .font(.headline)

                            Spacer()

                            Text(selectedCar.fuelTypeRaw)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    } else {
                        Text("Nessuna auto selezionata.")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } header: {
                    Text("Auto selezionata")
                        .foregroundStyle(Theme.text)
                }

                Section {
                    Picker("Carburante", selection: $selectedFuelType) {
                        Text("Benzina").tag("BENZINA")
                        Text("Diesel").tag("DIESEL")
                        Text("GPL").tag("GPL")
                        Text("Metano").tag("METANO")
                    }
                    .pickerStyle(.segmented)

                    Button {
                        Task {
                            await loadRecommendedStations()
                        }
                    } label: {
                        HStack {
                            if isLoadingStations {
                                ProgressView()
                            }

                            Text("Trova i 2 migliori distributori")
                        }
                    }
                    .disabled(isLoadingStations)

                    if let stationError {
                        Text(stationError)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if recommendedStations.isEmpty && !isLoadingStations {
                        Text("Nessun consiglio calcolato.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
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
                } header: {
                    Text("Dove conviene fare benzina")
                        .foregroundStyle(Theme.text)
                }

                Section {
                    if let selectedCar {
                        statRow("Statistiche auto", selectedCar.name)
                    }
                    statRow("Totale speso", totalSpent.formatted(.currency(code: "EUR")))
//                    statRow("Km totali tracciati", "\(Int(totalKm)) km")
                    statRow("Media km per euro", String(format: "%.2f km/€", kmPerEuro))
                    statRow("Numero rifornimenti", "\(carEntries.count)")
                } header: {
                    Text("Riepilogo")
                        .foregroundStyle(Theme.text)
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Theme.background)
            .background(Theme.background)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                loadCars()
                setFuelTypeFromSelectedCar()
                await loadRecommendedStations()
            }
            .onChange(of: selectedCarId) {
                loadCars()
                setFuelTypeFromSelectedCar()
                Task {
                    await loadRecommendedStations()
                }
            }
            .onChange(of: selectedFuelType) {
                Task {
                    await loadRecommendedStations()
                }
            }
            .navigationDestination(isPresented: $showingAdd) {
                AddFuelEntryView()
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
        }.scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    private func stationRow(_ station: GasStation, pairedStation: GasStation?) -> some View {
        let prices = mergedPrices(primary: station, secondary: pairedStation)

        return HStack {
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
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    selectedRecommendedStationId == station.id
                    ? Theme.accent.opacity(0.25)
                    : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRecommendedStationId = station.id
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

    private func setFuelTypeFromSelectedCar() {
        selectedFuelType = selectedCar?.fuelTypeRaw.uppercased() ?? "BENZINA"
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

    private func loadRecommendedStations() async {
        isLoadingStations = true
        stationError = nil

        let location = await locationService.requestLocation()

        guard let location else {
            isLoadingStations = false
            stationError = "Posizione non disponibile."
            return
        }

        do {
            let stations = try await FuelStationAPI.shared.bestStations(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                fuelType: fuelTypeForApi,
                liters: 30,
                carKmPerLiter: 15,
                radiusMeters: Int(stationSearchRadiusMeters),
                limit: 10
            )

            recommendedStations = Array(
                stations
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
                stationError = "Nessun distributore consigliato con prezzo aggiornato di recente."
            }

        } catch {
            stationError = "Non riesco a caricare i distributori consigliati."
            print("HOME BEST STATIONS ERROR:", error.localizedDescription)
        }

        isLoadingStations = false
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
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
}
