import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AccountSession.self) private var session
    @State private var layer: MapLayer = .knowledge
    @State private var places: [PlacePin] = []
    @State private var footprints: [Footprint] = []
    @State private var selectedPlace: PlacePin?
    @State private var showPlacePicker = false
    @State private var pendingFootprintPlace: PlacePin?
    @State private var draftPlace: PlacePin?
    @State private var loadState: MapLoadState = .idle
    @State private var footprintError: String?

    private var visiblePlaces: [PlacePin] {
        if layer == .knowledge { return places.filter { $0.linkCount > 0 } }
        let visited = Set(footprints.map(\.placeId))
        return places.filter { visited.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            PlaceMap(places: visiblePlaces, layer: layer) { place in
                selectedPlace = place
            }
            .ignoresSafeArea()

            HStack(spacing: 6) {
                layerButton(.knowledge, symbol: "play.rectangle.fill", title: "知", accessibilityTitle: "知，视频地图")
                layerButton(.journey, symbol: "figure.walk", title: "行", accessibilityTitle: "行，我的足迹地图")
            }
            .padding(5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.7)))
            .shadow(color: BrandTheme.ink.opacity(0.15), radius: 12, y: 5)
            .padding(.top, 12)

            if layer == .journey {
                VStack {
                    Spacer()
                    if footprints.isEmpty && !loadState.isLoading && footprintError == nil {
                        Text("还没有足迹。选一个地点，点亮你的行地图。")
                            .font(.subheadline)
                            .foregroundStyle(BrandTheme.ink)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button { showPlacePicker = true } label: {
                        Label("点亮地点", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.cinnabar)
                    .padding(.bottom, 24)
                }
            }

            if case let .failed(message) = loadState {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                    Text(message).multilineTextAlignment(.center)
                    Button("再试一次") { Task { await loadPlaces() } }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandTheme.pine)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(22)
                .frame(maxWidth: 300)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .frame(maxHeight: .infinity)
            }

            if let footprintError, layer == .journey {
                VStack(spacing: 8) {
                    Text(footprintError).multilineTextAlignment(.center)
                    Button("重试") { Task { await loadFootprints() } }
                }
                .font(.subheadline)
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxHeight: .infinity)
            }

            if loadState.isLoading {
                ProgressView("正在加载地点…")
                    .tint(BrandTheme.pine)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity)
            }
        }
        .task {
            await loadPlaces()
            await loadFootprints()
        }
        .sheet(item: $selectedPlace) { place in
            Group {
                if layer == .knowledge {
                    PlaceVideosSheet(place: place)
                } else {
                    FootprintPlaceSheet(place: place, footprints: footprints.filter { $0.placeId == place.id })
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPlacePicker, onDismiss: {
            draftPlace = pendingFootprintPlace
            pendingFootprintPlace = nil
        }) {
            FootprintPlacePicker(places: places) { place in
                pendingFootprintPlace = place
                showPlacePicker = false
            }
        }
        .sheet(item: $draftPlace) { place in
            FootprintDraftSheet(place: place) { date, note in
                try await addFootprint(at: place, date: date, note: note)
                draftPlace = nil
            }
        }
    }

    @MainActor
    private func loadPlaces() async {
        guard !loadState.isLoading else { return }
        loadState = .loading
        do {
            let allPlaces: [PlacePin] = try await APIClient.get("/places/pins")
            places = allPlaces
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func loadFootprints() async {
        guard let token = session.token else { return }
        do {
            footprints = try await APIClient.get("/me/footprints", bearer: token)
            footprintError = nil
        } catch {
            footprintError = "足迹加载失败，请重试。"
        }
    }

    @MainActor
    private func addFootprint(at place: PlacePin, date: Date, note: String) async throws {
        guard let token = session.token else { throw APIError.badResponse(401) }
        let body = NewFootprint(placeId: place.id,
                                date: ISO8601DateFormatter().string(from: date),
                                text: note.isEmpty ? nil : note,
                                visibility: "PRIVATE")
        let created: Footprint = try await APIClient.post("/footprints", body: body, bearer: token)
        footprints.insert(created, at: 0)
        footprintError = nil
        await loadFootprints()
    }

    private func layerButton(_ value: MapLayer, symbol: String, title: String, accessibilityTitle: String) -> some View {
        Button {
            selectedPlace = nil
            layer = value
            if value == .journey { Task { await loadFootprints() } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
            }
                .foregroundStyle(layer == value ? .white : BrandTheme.pine)
                .frame(width: 64)
                .padding(.vertical, 10)
                .background(layer == value ? BrandTheme.pine : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(layer == value ? .isSelected : [])
    }
}

private enum MapLayer { case knowledge, journey }

private struct NewFootprint: Encodable {
    let placeId: String
    let date: String
    let text: String?
    let visibility: String
}

private enum MapLoadState {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

private struct PlaceMap: UIViewRepresentable {
    let places: [PlacePin]
    let layer: MapLayer
    let onSelect: (PlacePin) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.showsScale = true
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.5, longitude: 104.0),
            span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 66)
        ), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.layer = layer
        let current = map.annotations.compactMap { $0 as? PlaceAnnotation }
        let currentIDs = Set(current.map(\.place.id))
        let newIDs = Set(places.map(\.id))
        guard currentIDs != newIDs || context.coordinator.renderedLayer != layer else { return }
        context.coordinator.renderedLayer = layer
        map.removeAnnotations(current)
        map.addAnnotations(places.map(PlaceAnnotation.init))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, layer: layer) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (PlacePin) -> Void
        var layer: MapLayer
        var renderedLayer: MapLayer?

        init(onSelect: @escaping (PlacePin) -> Void, layer: MapLayer) {
            self.onSelect = onSelect
            self.layer = layer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(layer == .knowledge ? BrandTheme.pine : BrandTheme.cinnabar)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                return view
            }
            guard let annotation = annotation as? PlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
                for: annotation
            ) as! MKMarkerAnnotationView
            view.canShowCallout = false
            view.markerTintColor = UIColor(layer == .knowledge ? BrandTheme.cinnabar : BrandTheme.pine)
            view.glyphImage = UIImage(systemName: layer == .knowledge ? "play.fill" : "figure.walk")
            view.clusteringIdentifier = layer == .knowledge ? "videos" : "footprints"
            view.accessibilityLabel = layer == .knowledge ? "\(annotation.place.name)，视频" : "\(annotation.place.name)，我的足迹"
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            defer { mapView.deselectAnnotation(view.annotation, animated: false) }
            guard let annotation = view.annotation as? PlaceAnnotation else { return }
            onSelect(annotation.place)
        }
    }
}

private final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: PlacePin
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(place: PlacePin) {
        self.place = place
        self.coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
        self.title = place.name
    }
}

private struct FootprintPlaceSheet: View {
    let place: PlacePin
    let footprints: [Footprint]

    var body: some View {
        NavigationStack {
            List {
                Section("我的足迹") {
                    ForEach(footprints) { footprint in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(footprint.date.prefix(10))
                                .font(.headline)
                            if let note = footprint.text, !note.isEmpty {
                                Text(note).font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BrandTheme.rice)
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FootprintPlacePicker: View {
    let places: [PlacePin]
    let onPick: (PlacePin) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [PlacePin] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? places : places.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { place in
                Button {
                    onPick(place)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(BrandTheme.cinnabar)
                        Text(place.name).foregroundStyle(BrandTheme.ink)
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(BrandTheme.pine)
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索地点")
            .navigationTitle("点亮地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}

private struct FootprintDraftSheet: View {
    let place: PlacePin
    let onSave: (Date, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("地点") { Text(place.name) }
                Section("这次旅行") {
                    DatePicker("到访日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("留一句话（可选）", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Label("这条足迹仅自己可见", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("点亮地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saving = true
                        Task {
                            do {
                                try await onSave(date, String(note.prefix(2000)))
                            } catch {
                                self.error = "保存失败，请稍后重试。"
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}
