import SwiftUI
import MapKit

struct FuelEntryDetailView: View {
    let entry: FuelEntry

    private var hasLocation: Bool {
        entry.latitude != nil && entry.longitude != nil
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = entry.latitude, let lon = entry.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        List {
            Section("Dettaglio") {
                LabeledContent("Importo", value: entry.amount.formatted(.currency(code: "EUR")))
                LabeledContent("Chilometri", value: "\(Int(entry.odometerKm)) km")
                LabeledContent("Data", value: entry.date.formatted(date: .abbreviated, time: .shortened))

                if let stationName = entry.stationName {
                    LabeledContent("Benzinaio", value: stationName)
                }

                if let address = entry.address {
                    LabeledContent("Indirizzo", value: address)
                }
            }

            if let coordinate {
                Section("Mappa") {
                    Map {
                        Marker("Rifornimento", coordinate: coordinate)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Section("Mappa") {
                    Text("Posizione non disponibile per questo rifornimento.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Rifornimento")
        .navigationBarTitleDisplayMode(.inline)
    }
}
