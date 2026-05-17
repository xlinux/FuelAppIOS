import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var fuelEntries: [FuelEntry]

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    @AppStorage("gpsTrackingEnabled") private var gpsTrackingEnabled: Bool = false
    @AppStorage("estimatedKmSinceLastRefuel") private var estimatedKmSinceLastRefuel: Double = 0
    @AppStorage("stationSearchRadiusMeters") private var stationSearchRadiusMeters: Double = 5000

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    @State private var cars: [CarInfo] = []
    @State private var isLoadingCars = false

    @State private var newCarName = ""
    @State private var newFuelType: FuelType = .benzina

    @State private var editingCar: CarInfo?
    @State private var editCarName = ""
    @State private var editFuelType: FuelType = .benzina

    @FocusState private var carNameFocused: Bool

    private var appTintColor: Color {
        if !newCarName.isEmpty {
            return colorForFuelType(newFuelType)
        }

        guard let selectedCar = cars.first(where: {
            $0.id.uuidString == selectedCarId
        }) else {
            return .orange
        }

        return colorForFuelType(selectedCar.fuelType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tema") {
                    Menu {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Button(theme.rawValue) {
                                appThemeRaw = theme.rawValue
                            }
                        }
                    } label: {
                        HStack {
                            Text("Aspetto")
                                .foregroundStyle(Color(uiColor: .label))
                            Spacer()

                            Text(appThemeRaw)
                                .foregroundStyle(appTintColor)

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(appTintColor)
                        }
                    }
                }

                Section("Aggiungi auto") {
                    TextField("Nome auto", text: $newCarName)
                        .focused($carNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            carNameFocused = false
                        }

                    Menu {
                        ForEach(FuelType.allCases, id: \.self) { type in
                            Button(type.rawValue) {
                                newFuelType = type
                            }
                        }
                    } label: {
                        HStack {
                            Text("Carburante")
                                .foregroundStyle(Color(uiColor: .label))

                            Spacer()

                            Text(newFuelType.rawValue)
                                .foregroundStyle(colorForFuelType(newFuelType))

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(colorForFuelType(newFuelType))
                        }
                    }

                    Button("Aggiungi auto") {
                        carNameFocused = false
                        addCar()
                    }
                    .disabled(
                        newCarName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }

                Section("Auto salvate") {
                    if isLoadingCars {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if cars.isEmpty {
                        Text("Nessuna auto salvata.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cars) { car in
                            Button {
                                selectedCarId = car.id.uuidString
                                saveCars()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(car.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text(car.fuelTypeRaw)
                                            .font(.caption)
                                            .foregroundStyle(colorForFuelType(car.fuelType))
                                    }

                                    Spacer()

                                    if selectedCarId == car.id.uuidString {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(colorForFuelType(car.fuelType))
                                    }

                                    Button {
                                        startEdit(car)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(colorForFuelType(car.fuelType))
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteCars)
                    }
                }

                Section("Ricerca distributori") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Raggio ricerca")

                            Spacer()

                            Text("\(Int(stationSearchRadiusMeters / 1000)) km")
                                .fontWeight(.semibold)
                                .foregroundStyle(appTintColor)
                        }

                        Slider(
                            value: $stationSearchRadiusMeters,
                            in: 2000...10000,
                            step: 1000
                        )
                        .tint(appTintColor)

                        Text("Usato per cercare distributori vicini e consigliati.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("GPS") {
                    Toggle(
                        "Traccia km con GPS",
                        isOn: $gpsTrackingEnabled
                    )
                    .tint(appTintColor)

                    Text("Km stimati dall’ultimo rifornimento: \(Int(estimatedKmSinceLastRefuel)) km")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Azzera km GPS stimati") {
                        estimatedKmSinceLastRefuel = 0
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .task {
                await loadCarsFromBackend()
            }
            .sheet(item: $editingCar) { car in
                NavigationStack {
                    Form {
                        TextField("Nome auto", text: $editCarName)

                        Menu {
                            ForEach(FuelType.allCases, id: \.self) { type in
                                Button(type.rawValue) {
                                    editFuelType = type
                                }
                            }
                        } label: {
                            HStack {
                                Text("Carburante")
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(editFuelType.rawValue)
                                    .foregroundStyle(colorForFuelType(editFuelType))

                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(colorForFuelType(editFuelType))
                            }
                        }
                    }
                    .navigationTitle("Modifica auto")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Annulla") {
                                editingCar = nil
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Salva") {
                                saveEditedCar(car)
                            }
                        }
                    }
                }
            }
        }
    }

    private func colorForFuelType(_ type: FuelType) -> Color {
        switch type {
        case .benzina:
            return .orange
        case .diesel:
            return .indigo
        case .gpl:
            return .green
            
        case .metano:
            return .blue
        }
    }

    private func addCar() {
        let name = newCarName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        Task {
            do {
                let remote = try await UserDataAPI.shared.createCar(
                    name: name,
                    fuelType: newFuelType.rawValue,
                    defaultCar: cars.isEmpty
                )

                let car = CarInfo(
                    id: UUID(uuidString: remote.id) ?? UUID(),
                    name: remote.name,
                    fuelTypeRaw: remote.fuelType.capitalized
                )

                await MainActor.run {
                    cars.append(car)

                    if selectedCarId.isEmpty {
                        selectedCarId = car.id.uuidString
                    }

                    newCarName = ""
                    newFuelType = .benzina

                    saveCars()
                }

            } catch {
                print("ERRORE CREAZIONE AUTO BACKEND:", error.localizedDescription)
            }
        }
    }

    private func startEdit(_ car: CarInfo) {
        editingCar = car
        editCarName = car.name
        editFuelType = car.fuelType
    }

    private func saveEditedCar(_ car: CarInfo) {
        let name = editCarName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        let oldName = car.name
        let isDefault = selectedCarId == car.id.uuidString

        Task {
            do {
                let remote = try await UserDataAPI.shared.updateCar(
                    id: car.id.uuidString,
                    name: name,
                    fuelType: editFuelType.rawValue,
                    defaultCar: isDefault
                )

                await MainActor.run {
                    if let index = cars.firstIndex(where: { $0.id == car.id }) {
                        cars[index] = CarInfo(
                            id: UUID(uuidString: remote.id) ?? car.id,
                            name: remote.name,
                            fuelTypeRaw: remote.fuelType.capitalized
                        )
                    }

                    for entry in fuelEntries where entry.carName == oldName {
                        entry.carName = remote.name
                        entry.fuelTypeRaw = remote.fuelType.capitalized
                    }

                    do {
                        try modelContext.save()
                    } catch {
                        print("ERRORE UPDATE RIFORNIMENTI LOCALI AUTO:", error.localizedDescription)
                    }

                    saveCars()
                    editingCar = nil
                }

            } catch {
                print("ERRORE UPDATE AUTO BACKEND:", error.localizedDescription)
            }
        }
    }

    private func deleteCars(at offsets: IndexSet) {
        for index in offsets {
            let removed = cars[index]

            Task {
                do {
                    try await UserDataAPI.shared.deleteCar(
                        id: removed.id.uuidString
                    )
                } catch {
                    print("ERRORE DELETE AUTO BACKEND:", error.localizedDescription)
                }
            }

            for entry in fuelEntries where entry.carName == removed.name {
                modelContext.delete(entry)
            }

            if selectedCarId == removed.id.uuidString {
                selectedCarId = ""
            }
        }

        cars.remove(atOffsets: offsets)

        if selectedCarId.isEmpty,
           let first = cars.first {
            selectedCarId = first.id.uuidString
        }

        saveCars()

        do {
            try modelContext.save()
        } catch {
            print("ERRORE ELIMINAZIONE AUTO/RIFORNIMENTI:", error.localizedDescription)
        }
    }

    private func loadCarsFromBackend() async {
        await MainActor.run {
            isLoadingCars = true
        }

        do {
            let remoteCars = try await UserDataAPI.shared.fetchCars()

            let mappedCars = remoteCars.map {
                CarInfo(
                    id: UUID(uuidString: $0.id) ?? UUID(),
                    name: $0.name,
                    fuelTypeRaw: $0.fuelType.capitalized
                )
            }

            await MainActor.run {
                cars = mappedCars

                if selectedCarId.isEmpty,
                   let first = mappedCars.first {
                    selectedCarId = first.id.uuidString
                }

                saveCars()
                isLoadingCars = false
            }

        } catch {
            print("ERRORE LOAD AUTO BACKEND:", error.localizedDescription)

            await MainActor.run {
                loadCars()
                isLoadingCars = false
            }
        }
    }

    private func loadCars() {
        guard
            let data = carsJson.data(using: .utf8),
            let decoded = try? JSONDecoder()
                .decode([CarInfo].self, from: data)
        else {
            cars = []
            return
        }

        cars = decoded
    }

    private func saveCars() {
        guard
            let data = try? JSONEncoder().encode(cars),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        carsJson = json
    }
}
