import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UIKit

struct StationsMapView: View {
    private struct MergedStation: Identifiable {
        let id: UUID
        let primary: GasStation
        let secondary: GasStation?
    }

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
    @State private var selectedStationIndex = 0
    @State private var mapCenterCoordinate: CLLocationCoordinate2D?
    @State private var lastSearchedCenter: CLLocationCoordinate2D?
    @State private var hasInitializedCamera = false
    @State private var selectedFuelType: String = "BENZINA"

    private let locationService = LocationService()

    private var selectedCar: CarInfo? {
        cars.first { $0.id.uuidString == selectedCarId }
    }

    private var mergedStations: [MergedStation] {
        var result: [MergedStation] = []
        var index = 0

        while index < gasStations.count {
            let primary = gasStations[index]
            let nextIndex = index + 1
            let secondary: GasStation? = {
                guard nextIndex < gasStations.count else { return nil }
                return stationKey(primary) == stationKey(gasStations[nextIndex]) ? gasStations[nextIndex] : nil
            }()

            result.append(
                MergedStation(
                    id: primary.id,
                    primary: primary,
                    secondary: secondary
                )
            )

            index += (secondary == nil ? 1 : 2)
        }

        return result
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

                    ForEach(mergedStations) { merged in
                        let station = merged.primary
                        let prices = mergedPrices(primary: merged.primary, secondary: merged.secondary)

                        Annotation(station.name, coordinate: station.coordinate) {
                            Button {
                                selectedStation = station
                                if let index = mergedStations.firstIndex(where: { $0.id == merged.id }) {
                                    selectedStationIndex = index
                                }
                                moveMap(to: station, meters: 800)
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
                                            .foregroundStyle(.black)
                                            .frame(width: 32, height: 32)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(station.name)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                            .foregroundStyle(.black)

                                        if let selfPrice = prices.selfPrice {
                                            Text("Self \(String(format: "%.3f €/L", selfPrice))")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        } else if let servedPrice = prices.servedPrice {
                                            Text("Serv \(String(format: "%.3f €/L", servedPrice))")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white)
.foregroundStyle(Theme.text)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapCenterCoordinate = context.region.center
                }
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    fuelTypePicker
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                VStack(spacing: 8) {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Ricerca distributori...")
                                .font(.caption)
                        }
                        .padding(10)
                        .background(Color.white)
.foregroundStyle(Theme.text)
                        .clipShape(Capsule())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                            .background(Color.white)
.foregroundStyle(Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if !mergedStations.isEmpty {
                        TabView(selection: $selectedStationIndex) {
                            ForEach(Array(mergedStations.enumerated()), id: \.element.id) { index, merged in
                                selectedStationCard(primary: merged.primary, secondary: merged.secondary)
                                    .padding(.horizontal)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: 190)
                    }
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("Mappa distributori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadStations(centerOverride: mapCenterCoordinate)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                Task {
                    await recenterOnCurrentLocationAndReload()
                }
            }
            .task {
                loadCars()
                setFuelTypeFromSelectedCar()
            }
            .onChange(of: selectedCarId) {
                Task {
                    loadCars()
                    setFuelTypeFromSelectedCar()
                    await loadStations(centerOverride: mapCenterCoordinate)
                }
            }
            .onChange(of: selectedFuelType) {
                Task {
                    await loadStations(centerOverride: mapCenterCoordinate)
                }
            }
            .onChange(of: selectedStationIndex) {
                guard mergedStations.indices.contains(selectedStationIndex) else { return }
                let station = mergedStations[selectedStationIndex].primary
                selectedStation = station
                moveMap(to: station, meters: 800)
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
        .background(Color.white)
        .foregroundStyle(Theme.text)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func fuelTypeDisplayName(_ value: String) -> String {
        switch value.uppercased() {
        case "DIESEL":
            return "Diesel"
        case "GPL":
            return "GPL"
        case "METANO":
            return "Metano"
        case "BENZINA":
            return "Benzina"
        default:
            return value.capitalized
        }
    }

    private func stationKey(_ station: GasStation) -> String {
        let address = (station.address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(station.name.lowercased())|\(address)"
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

    private func selectedStationCard(primary station: GasStation, secondary: GasStation?) -> some View {
        let prices = mergedPrices(primary: station, secondary: secondary)
        let hasBothPrices = prices.selfPrice != nil && prices.servedPrice != nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {

                    if let logoName = StationLogoHelper.imageName(for: station.name) {
                        Image(logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Text(station.name)
                        .font(.headline)
                        .foregroundStyle(.black)
                }

                Spacer()

                if !hasBothPrices, let selfPrice = prices.selfPrice {
                    Text("Self \(String(format: "%.3f €/L", selfPrice))")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else if !hasBothPrices, let servedPrice = prices.servedPrice {
                    Text("Servito \(String(format: "%.3f €/L", servedPrice))")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }

            if let address = station.address {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack {
                Text("\(Int(station.distanceMeters)) metri")
                    .font(.caption)
                    .foregroundStyle(.gray)

                if let updated = station.priceUpdatedAtFormatted {
                    Text("\(station.priceFreshnessDot) \(updated)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                if !hasBothPrices, let isSelfService = station.selfService {
                    Text(isSelfService ? "Self" : "Servito")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelfService ? .blue : .orange)
                }
            }

            if hasBothPrices, let selfPrice = prices.selfPrice, let servedPrice = prices.servedPrice {
                HStack {
                    Text("Self \(String(format: "%.3f €/L", selfPrice))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)

                    Spacer()

                    Text("Servito \(String(format: "%.3f €/L", servedPrice))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 10) {
                Button {
                    openInAppleMaps(station)
                } label: {
                    Label("Maps", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button {
                    openInGoogleMaps(station)
                } label: {
                    Label("Google", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            .font(.caption)

        }
        .padding()
        .background(Color.white)
        .foregroundStyle(.black)
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

    private func loadStations(centerOverride: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        errorMessage = nil

        var searchCoordinate = centerOverride

        if searchCoordinate == nil {
            if let existingCenter = mapCenterCoordinate {
                searchCoordinate = existingCenter
            } else {
                let location = await locationService.requestLocation()
                currentLocation = location

                guard let location else {
                    gasStations = []
                    selectedStation = nil
                    errorMessage = "Posizione non disponibile."
                    isLoading = false
                    return
                }

                let userCoordinate = location.coordinate
                searchCoordinate = userCoordinate
                mapCenterCoordinate = userCoordinate

                if !hasInitializedCamera {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: userCoordinate,
                            latitudinalMeters: 1200,
                            longitudinalMeters: 1200
                        )
                    )
                    hasInitializedCamera = true
                }
            }
        }

        guard let searchCoordinate else {
            gasStations = []
            selectedStation = nil
            errorMessage = "Posizione non disponibile."
            isLoading = false
            return
        }

        do {
            let stations = try await FuelStationAPI.shared.nearbyStations(
                lat: searchCoordinate.latitude,
                lng: searchCoordinate.longitude,
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
            selectedStationIndex = 0
            lastSearchedCenter = searchCoordinate

        } catch {
            gasStations = []
            selectedStation = nil
            errorMessage = "Non riesco a caricare i distributori."
            print("MAP STATIONS ERROR:", error.localizedDescription)
        }

        isLoading = false
    }

    private func recenterOnCurrentLocationAndReload() async {
        let location = await locationService.requestLocation()
        currentLocation = location

        guard let location else {
            return
        }

        let coordinate = location.coordinate
        mapCenterCoordinate = coordinate
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            )
        )

        await loadStations(centerOverride: coordinate)
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

    private func shouldReloadStations(for newCenter: CLLocationCoordinate2D) -> Bool {
        guard let previousCenter = lastSearchedCenter else {
            return true
        }

        let previous = CLLocation(latitude: previousCenter.latitude, longitude: previousCenter.longitude)
        let current = CLLocation(latitude: newCenter.latitude, longitude: newCenter.longitude)
        return previous.distance(from: current) > 250
    }

    private func openInAppleMaps(_ station: GasStation) {
        let coordinate = CLLocationCoordinate2D(
            latitude: station.coordinate.latitude,
            longitude: station.coordinate.longitude
        )
        let placemark = MKPlacemark(coordinate: coordinate)
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
