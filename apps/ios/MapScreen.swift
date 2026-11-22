import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AccountSession.self) private var session
    @State private var layer: MapLayer = .knowledge
    @State private var places: [PlacePin] = []
    @State private var footprints: [Footprint] = []
    @State private var selection: MapSelection?
    @State private var showKnowledgeSearch = false
    @State private var showWelcome = false
    @State private var pendingSearchPlace: PlacePin?
    @State private var mapFocus: MapFocus?
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
            PlaceMap(places: visiblePlaces, layer: layer, focus: mapFocus) { selection in
                mapFocus = nil
                self.selection = selection
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

            if layer == .knowledge {
                HStack {
                    Menu {
                        Button("重看欢迎页", systemImage: "play.rectangle") {
                            UserDefaults.standard.removeObject(forKey: WelcomeFlowPersistence.pageKey)
                            withAnimation(.easeInOut(duration: 0.38)) {
                                showWelcome = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BrandTheme.pine)
                            .frame(width: 48, height: 48)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.7)))
                            .shadow(color: BrandTheme.ink.opacity(0.15), radius: 12, y: 5)
                    }
                    .accessibilityLabel("更多选项")
                    Spacer()
                    Button { showKnowledgeSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BrandTheme.pine)
                            .frame(width: 48, height: 48)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.7)))
                            .shadow(color: BrandTheme.ink.opacity(0.15), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索有视频的地点")
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
            }

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

            if showWelcome {
                WelcomeVideoFeed {
                    showWelcome = false
                }
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .zIndex(1)
            }
        }
        .task {
            await loadPlaces()
            await loadFootprints()
        }
        .sheet(item: $selection) { selection in
            Group {
                switch selection {
                case let .place(place) where layer == .knowledge:
                    PlaceVideosSheet(place: place)
                case let .place(place):
                    FootprintPlaceSheet(place: place, footprints: footprints.filter { $0.placeId == place.id })
                case let .nearbyPlaces(places):
                    NearbyPlacesSheet(places: places) { place in
                        self.selection = .place(place)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showKnowledgeSearch, onDismiss: openSearchResult) {
            KnowledgePlaceSearch(places: visiblePlaces, allPlaces: places) { place in
                pendingSearchPlace = place
                showKnowledgeSearch = false
            }
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

    private func openSearchResult() {
        guard layer == .knowledge, let place = pendingSearchPlace else {
            pendingSearchPlace = nil
            return
        }
        pendingSearchPlace = nil
        let focus = MapFocus(place: place)
        mapFocus = focus
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard layer == .knowledge, mapFocus?.id == focus.id else { return }
            selection = .place(place)
        }
    }

    private func layerButton(_ value: MapLayer, symbol: String, title: String, accessibilityTitle: String) -> some View {
        Button {
            selection = nil
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

private struct MapFocus {
    let id = UUID()
    let place: PlacePin
}

private enum MapSelection: Identifiable {
    case place(PlacePin)
    case nearbyPlaces([PlacePin])

    var id: String {
        switch self {
        case let .place(place): "place:\(place.id)"
        case .nearbyPlaces: "nearbyPlaces"
        }
    }
}

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
    let focus: MapFocus?
    let onSelect: (MapSelection) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        compass.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(compass)
        let scale = MKScaleView(mapView: map)
        scale.scaleVisibility = .adaptive
        scale.legendAlignment = .leading
        scale.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(scale)
        NSLayoutConstraint.activate([
            compass.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            compass.topAnchor.constraint(equalTo: map.topAnchor, constant: 150),
            scale.leadingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scale.bottomAnchor.constraint(equalTo: map.safeAreaLayoutGuide.bottomAnchor, constant: -42)
        ])
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.register(VideoClusterAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: VideoClusterAnnotationView.reuseIdentifier)
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
        if currentIDs != newIDs || context.coordinator.renderedLayer != layer {
            context.coordinator.renderedLayer = layer
            context.coordinator.zoomingTo = []
            map.removeAnnotations(current)
            map.addAnnotations(places.map(PlaceAnnotation.init))
        }
        if let focus, context.coordinator.renderedFocusID != focus.id {
            context.coordinator.renderedFocusID = focus.id
            let delta = focus.place.level == "POI" ? 0.04 : 0.3
            // Keep the selected pin in the upper quarter, above the medium video sheet.
            let centerLatitude = focus.place.lat - delta * 0.25
            map.setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLatitude, longitude: focus.place.lng),
                span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
            ), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, layer: layer) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (MapSelection) -> Void
        var layer: MapLayer
        var renderedLayer: MapLayer?
        var renderedFocusID: UUID?
        var zoomingTo: [PlaceAnnotation] = []

        init(onSelect: @escaping (MapSelection) -> Void, layer: MapLayer) {
            self.onSelect = onSelect
            self.layer = layer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                if layer == .knowledge {
                    let view = mapView.dequeueReusableAnnotationView(
                        withIdentifier: VideoClusterAnnotationView.reuseIdentifier,
                        for: cluster
                    ) as! VideoClusterAnnotationView
                    view.setPlaceCount(cluster.memberAnnotations.count)
                    return view
                }
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(BrandTheme.cinnabar)
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
            zoomingTo = []
            if let annotation = view.annotation as? PlaceAnnotation {
                onSelect(.place(annotation.place))
            } else if layer == .knowledge, let cluster = view.annotation as? MKClusterAnnotation {
                zoom(to: cluster, on: mapView)
            }
        }

        private func zoom(to cluster: MKClusterAnnotation, on mapView: MKMapView) {
            let members = cluster.memberAnnotations.compactMap { $0 as? PlaceAnnotation }
            guard members.count > 1 else { return }

            let bounds = members.reduce(MKMapRect.null) { bounds, member in
                let point = MKMapPoint(member.coordinate)
                return bounds.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
            }
            // Give coincident pins a street-level zoom target.
            let minimumSpan = 160 * MKMapPointsPerMeterAtLatitude(cluster.coordinate.latitude)
            let width = max(bounds.width, minimumSpan)
            let height = max(bounds.height, minimumSpan)
            let target = MKMapRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                                   width: width, height: height)
            let padding = UIEdgeInsets(top: 96, left: 48, bottom: 72, right: 48)
            let fitted = mapView.mapRectThatFits(target, edgePadding: padding)

            guard fitted.width < mapView.visibleMapRect.width * 0.95 else {
                onSelect(.nearbyPlaces(members.map(\.place)))
                return
            }
            zoomingTo = members
            mapView.setVisibleMapRect(target, edgePadding: padding, animated: true)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let members = zoomingTo
            zoomingTo = []
            guard !members.isEmpty, layer == .knowledge, animated else { return }

            // Check screen positions because MapKit can update its cluster views after this callback.
            let points = members.map { mapView.convert($0.coordinate, toPointTo: mapView) }
            let bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            let minimumTapSpacing: CGFloat = 44
            if bounds.width < minimumTapSpacing, bounds.height < minimumTapSpacing, mapView.bounds.contains(bounds) {
                onSelect(.nearbyPlaces(members.map(\.place)))
            }
        }
    }
}

private final class VideoClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "VideoCluster"

    private let countBadge = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // MapKit draws a count inside native cluster markers even when a glyph is set.
        image = Self.playPin
        centerOffset = CGPoint(x: 0, y: -16)
        collisionMode = .circle
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "轻点放大地图或选择地点"
        clipsToBounds = false

        countBadge.backgroundColor = UIColor(BrandTheme.pineDeep)
        countBadge.textColor = .white
        countBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 9
        countBadge.layer.borderWidth = 1
        countBadge.layer.borderColor = UIColor.white.cgColor
        countBadge.clipsToBounds = true
        countBadge.isAccessibilityElement = false
        addSubview(countBadge)
    }

    required init?(coder: NSCoder) {
        fatalError("VideoClusterAnnotationView is created programmatically")
    }

    func setPlaceCount(_ count: Int) {
        countBadge.text = count.formatted()
        accessibilityLabel = "\(count) 个视频地点"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height: CGFloat = 18
        let width = max(height, ceil(countBadge.intrinsicContentSize.width) + 8)
        countBadge.frame = CGRect(x: bounds.maxX - width + 6, y: bounds.minY - 5,
                                  width: width, height: height)
        bringSubviewToFront(countBadge)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || countBadge.frame.contains(point)
    }

    private static let playPin = UIGraphicsImageRenderer(size: CGSize(width: 34, height: 38)).image { renderer in
        let pin = UIBezierPath(arcCenter: CGPoint(x: 17, y: 16), radius: 13,
                               startAngle: .pi * 0.66, endAngle: .pi * 2.34, clockwise: true)
        pin.addQuadCurve(to: CGPoint(x: 17, y: 32), controlPoint: CGPoint(x: 20, y: 29))
        pin.addQuadCurve(to: CGPoint(x: 10.7, y: 27.4), controlPoint: CGPoint(x: 14, y: 29))
        pin.close()

        let context = renderer.cgContext
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.25).cgColor)
        UIColor(BrandTheme.cinnabar).setFill()
        pin.fill()
        context.restoreGState()
        UIColor.white.setStroke()
        pin.lineWidth = 2
        pin.lineJoinStyle = .round
        pin.stroke()

        UIImage(systemName: "play.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
            .draw(in: CGRect(x: 12, y: 9, width: 12, height: 14))
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

private struct KnowledgePlaceSearch: View {
    let places: [PlacePin]
    let allPlaces: [PlacePin]
    let onPick: (PlacePin) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""

    private let aliases: [String: [String]] = [
        "江之岛": ["江ノ島", "江の島", "Enoshima"],
        "甲斐駒ヶ岳": ["甲斐驹岳", "甲斐駒岳", "Kaikomagatake", "Mount Kaikoma"]
    ]

    private var results: [PlacePin] {
        let term = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !term.isEmpty else { return [] }
        return places.filter { place in
            ([place.name] + (aliases[place.name] ?? [])).contains {
                normalized($0).contains(term)
            }
        }
        .sorted { lhs, rhs in
            let left = normalized(lhs.name)
            let right = normalized(rhs.name)
            let leftRank = left == term ? 0 : left.hasPrefix(term) ? 1 : 2
            let rightRank = right == term ? 0 : right.hasPrefix(term) ? 1 : 2
            return leftRank == rightRank
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : leftRank < rightRank
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(BrandTheme.pine)
                    TextField("搜索地点", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("寻找地点", systemImage: "mappin.and.ellipse")
                        .frame(maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView("没有找到地点", systemImage: "magnifyingglass",
                                           description: Text("这个地点暂时没有视频"))
                        .frame(maxHeight: .infinity)
                } else {
                    List(results) { place in
                        Button { onPick(place) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title3)
                                    .foregroundStyle(BrandTheme.cinnabar)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(BrandTheme.ink)
                                    Text(resultSubtitle(for: place))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "location")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(BrandTheme.rice.ignoresSafeArea())
            .navigationTitle("搜索地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .task { searchFocused = true }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "江ノ島", with: "江之岛")
            .replacingOccurrences(of: "江の島", with: "江之岛")
            .replacingOccurrences(of: "島", with: "岛")
            .replacingOccurrences(of: "駒", with: "驹")
    }

    private func resultSubtitle(for place: PlacePin) -> String {
        let count = "\(place.linkCount) 个视频"
        guard let parentId = place.parentId,
              let parent = allPlaces.first(where: { $0.id == parentId }) else { return count }
        return "\(parent.name) · \(count)"
    }
}

private struct NearbyPlacesSheet: View {
    let places: [PlacePin]
    let onSelect: (PlacePin) -> Void

    var body: some View {
        NavigationStack {
            List(places.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { place in
                Button {
                    onSelect(place)
                } label: {
                    HStack {
                        Label(place.name, systemImage: "play.rectangle.fill")
                            .foregroundStyle(BrandTheme.ink)
                        Spacer()
                        Text("\(place.linkCount) 个视频")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BrandTheme.rice)
            .navigationTitle("这附近的 \(places.count) 个地点")
            .navigationBarTitleDisplayMode(.inline)
        }
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
