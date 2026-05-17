import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UIKit

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
    @State private var selectedFuelType: String = "BENZINA"

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
                    fuelTypePicker
                        .padding(.horizontal)

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
                setFuelTypeFromSelectedCar()
                await loadStations()
            }
            .onChange(of: selectedCarId) {
                Task {
                    loadCars()
                    setFuelTypeFromSelectedCar()
                    await loadStations()
                }
            }
            .onChange(of: selectedFuelType) {
                Task {
                    await loadStations()
                }
            }
        }
    }

    private var fuelTypePicker: some View {
        Picker("Carburante", selection: $selectedFuelType) {
            Text("Benzina").tag("BENZINA")
            Text("Diesel").tag("DIESEL")
            Text("Gpl").tag("GPL")
            Text("Metano").tag("METANO")
        }
        .pickerStyle(.segmented)
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func selectedStationCard(_ station: GasStation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(spacing: 10) {
                Button {
                    openInAppleMaps(station)
                } label: {
                    Label("Maps", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openInGoogleMaps(station)
                } label: {
                    Label("Google", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
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

    private func setFuelTypeFromSelectedCar() {
        guard let selectedCar else {
            selectedFuelType = "BENZINA"
            return
        }

        selectedFuelType = selectedCar.fuelTypeRaw.uppercased()
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
            let stations = try await FuelStationAPI.shared.nearbyStations(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                fuelType: selectedFuelType,
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

    private func openInAppleMaps(_ station: GasStation) {
        let placemark = MKPlacemark(coordinate: station.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = station.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openInGoogleMaps(_ station: GasStation) {
        let urlString = "comgooglemaps://?daddr=\(station.coordinate.latitude),\(station.coordinate.longitude)&directionsmode=driving"

        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        let browserUrlString = "https://www.google.com/maps/dir/?api=1&destination=\(station.coordinate.latitude),\(station.coordinate.longitude)&travelmode=driving"

        if let browserUrl = URL(string: browserUrlString) {
            UIApplication.shared.open(browserUrl)
        }
    }
}
