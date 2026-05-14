import SwiftUI

struct SettingsView: View {

    @AppStorage("carsJson") private var carsJson: String = ""
    @AppStorage("selectedCarId") private var selectedCarId: String = ""

    @AppStorage("gpsTrackingEnabled") private var gpsTrackingEnabled: Bool = false
    @AppStorage("estimatedKmSinceLastRefuel") private var estimatedKmSinceLastRefuel: Double = 0

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    @State private var cars: [CarInfo] = []

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
                    if cars.isEmpty {
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
            .onAppear {
                loadCars()
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
        case .elettrico:
            return .green
        }
    }

    private func addCar() {
        let name = newCarName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        let car = CarInfo(
            name: name,
            fuelTypeRaw: newFuelType.rawValue
        )

        cars.append(car)

        if selectedCarId.isEmpty {
            selectedCarId = car.id.uuidString
        }

        newCarName = ""
        newFuelType = .benzina

        saveCars()
    }

    private func startEdit(_ car: CarInfo) {
        editingCar = car
        editCarName = car.name
        editFuelType = car.fuelType
    }

    private func saveEditedCar(_ car: CarInfo) {
        guard let index = cars.firstIndex(where: {
            $0.id == car.id
        }) else {
            editingCar = nil
            return
        }

        let name = editCarName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        cars[index].name = name
        cars[index].fuelType = editFuelType

        saveCars()
        editingCar = nil
    }

    private func deleteCars(at offsets: IndexSet) {
        for index in offsets {
            let removed = cars[index]

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
