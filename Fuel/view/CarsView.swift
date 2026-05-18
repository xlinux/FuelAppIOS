import SwiftUI

struct CarsView: View {

    @AppStorage("carsList") private var carsList: String = ""
    @AppStorage("selectedCarName") private var selectedCarName: String = ""

    @State private var newCarName = ""
    @State private var newFuelType: FuelType = .benzina

    @FocusState private var carNameFocused: Bool

    private var cars: [String] {
        carsList
            .split(separator: "|")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {

                    TextField("Nome auto", text: $newCarName)
                        .focused($carNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            carNameFocused = false
                        }

                    Picker("Carburante", selection: $newFuelType) {
                        ForEach(FuelType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Button("Aggiungi auto") {
                        addCar()
                    }
                    .disabled(newCarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Aggiungi auto")
                        .foregroundStyle(Theme.text)
                }

                Section {

                    if cars.isEmpty {
                        Text("Nessuna auto salvata.")
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        ForEach(cars, id: \.self) { car in
                            Button {
                                selectedCarName = car
                            } label: {
                                HStack {
                                    Text(car)

                                    Spacer()

                                    if selectedCarName == car {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteCars)
                    }
                } header: {
                    Text("Auto salvate")
                        .foregroundStyle(Theme.text)
                }
            }
            .foregroundStyle(.black)
            .navigationTitle("Auto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollContentBackground(.hidden)
            
            .background(Theme.background)
        }
    }

    private func addCar() {
        let name = newCarName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        var currentCars = cars

        if !currentCars.contains(name) {
            currentCars.append(name)
        }

        carsList = currentCars.joined(separator: "|")

        if selectedCarName.isEmpty {
            selectedCarName = name
        }

        newCarName = ""
        carNameFocused = false
    }

    private func deleteCars(at offsets: IndexSet) {
        var currentCars = cars

        for index in offsets {
            let removed = currentCars[index]

            if selectedCarName == removed {
                selectedCarName = ""
            }
        }

        currentCars.remove(atOffsets: offsets)
        carsList = currentCars.joined(separator: "|")
    }
}
