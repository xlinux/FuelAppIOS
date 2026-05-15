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
        selectedCar?.fuelTypeRaw.uppercased() ?? "BENZINA"
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
                                    .foregroundStyle(.secondary)
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

                Section("Auto selezionata") {
                    if let selectedCar {
                        HStack {
                            Image(systemName: "car.fill")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedCar.name)
                                    .font(.headline)

                                Text(selectedCar.fuelTypeRaw)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Nessuna auto selezionata.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Dove conviene fare benzina") {
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
                            .foregroundStyle(.secondary)
                    }

                    if recommendedStations.isEmpty && !isLoadingStations {
                        Text("Nessun consiglio calcolato.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recommendedStations) { station in
                            stationRow(station)
                        }
                    }
                }

                Section("Riepilogo") {
                    if let selectedCar {
                        statRow("Statistiche auto", selectedCar.name)
                    }
                    statRow("Totale speso", totalSpent.formatted(.currency(code: "EUR")))
                    statRow("Km totali tracciati", "\(Int(totalKm)) km")
                    statRow("Media km per euro", String(format: "%.2f km/€", kmPerEuro))
                    statRow("Numero rifornimenti", "\(carEntries.count)")
                }
            }
            .navigationTitle("Home")
            .task {
                loadCars()
                await loadRecommendedStations()
            }
            .sheet(isPresented: $showingAdd) {
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
        }
    }

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

                Text("Tieni premuto per aprire Maps")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "map")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
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
}
