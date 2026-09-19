import MapKit
import UIKit

final class PhotoCluster: NSObject, MKAnnotation {

    let coordinate: CLLocationCoordinate2D
    let count: Int
    let photo: Photo
    let key: Int64

    init(coordinate: CLLocationCoordinate2D, count: Int, photo: Photo, key: Int64) {
        self.coordinate = coordinate
        self.count = count
        self.photo = photo
        self.key = key
        super.init()
    }
}

enum MapClustering {

    private struct Bucket {
        var latitude: Double = 0
        var longitude: Double = 0
        var count: Int = 0
        var first: Int = 0
    }

    static func cellSize(for span: MKCoordinateSpan) -> Double {
        let zoom = floor(log2(360 / max(span.longitudeDelta, 0.0005)))
        return 45 / pow(2, max(0, zoom))
    }

    static func key(latitude: Double, longitude: Double, cell: Double) -> Int64 {
        let row = Int64(floor(latitude / cell))
        let column = Int64(floor(longitude / cell))
        return row &* 0x1_0000_0000 &+ column
    }

    static func clusters(for locations: [PhotoLocation],
                         in region: MKCoordinateRegion,
                         cell: Double) -> [Int64: PhotoCluster] {
        let latitudePadding = region.span.latitudeDelta * 0.75
        let longitudePadding = region.span.longitudeDelta * 0.75
        let minLatitude = region.center.latitude - latitudePadding
        let maxLatitude = region.center.latitude + latitudePadding
        let minLongitude = region.center.longitude - longitudePadding
        let maxLongitude = region.center.longitude + longitudePadding

        var buckets: [Int64: Bucket] = [:]
        for (index, location) in locations.enumerated() {
            guard location.latitude >= minLatitude, location.latitude <= maxLatitude,
                  location.longitude >= minLongitude, location.longitude <= maxLongitude else {
                continue
            }

            let bucketKey = key(latitude: location.latitude, longitude: location.longitude, cell: cell)
            var bucket = buckets[bucketKey] ?? Bucket(latitude: 0, longitude: 0, count: 0, first: index)
            bucket.latitude += location.latitude
            bucket.longitude += location.longitude
            bucket.count += 1
            buckets[bucketKey] = bucket
        }

        var clusters: [Int64: PhotoCluster] = [:]
        clusters.reserveCapacity(buckets.count)
        for (bucketKey, bucket) in buckets {
            let center = CLLocationCoordinate2D(latitude: bucket.latitude / Double(bucket.count),
                                                longitude: bucket.longitude / Double(bucket.count))
            clusters[bucketKey] = PhotoCluster(coordinate: center,
                                               count: bucket.count,
                                               photo: locations[bucket.first].photo,
                                               key: bucketKey)
        }
        return clusters
    }
}

final class MapViewController: UIViewController {

    private let services: AppServices

    private var mapView: MKMapView!
    private let closeButton = FloatingButton(glyph: CloseGlyphView())
    private let messagePill = SquircleView()
    private let messageLabel = UILabel()

    private var locations: [PhotoLocation] = []
    private var displayed: [Int64: PhotoCluster] = [:]
    private var cell: Double = 0

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()

        services.store.locations { [weak self] locations in
            guard let self = self else { return }
            self.locations = locations
            self.showMessage(locations.isEmpty ? "No photos carry a location yet" : nil)
            self.frameContent()
            self.rebuildClusters()
        }
    }

    private func buildHierarchy() {
        let palette = Theme.palette
        view.backgroundColor = palette.background

        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsCompass = false
        mapView.register(PhotoMarkerView.self,
                         forAnnotationViewWithReuseIdentifier: PhotoMarkerView.reuseIdentifier)
        view.addSubview(mapView)

        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        messagePill.cornerRadius = 15
        messagePill.fillColor = palette.surface
        messagePill.applyShadow(palette)
        messagePill.isHidden = true
        messagePill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messagePill)

        messageLabel.font = Typography.caption
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = palette.textSecondary
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messagePill.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                 constant: 12),

            messagePill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messagePill.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messagePill.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                 constant: 24),

            messageLabel.leadingAnchor.constraint(equalTo: messagePill.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: messagePill.trailingAnchor, constant: -16),
            messageLabel.topAnchor.constraint(equalTo: messagePill.topAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(equalTo: messagePill.bottomAnchor, constant: -8)
        ])
    }

    private func showMessage(_ text: String?) {
        messageLabel.text = text
        messagePill.isHidden = text == nil
    }

    private func frameContent() {
        guard !locations.isEmpty else { return }

        var minLatitude = 90.0
        var maxLatitude = -90.0
        var minLongitude = 180.0
        var maxLongitude = -180.0
        for location in locations {
            minLatitude = min(minLatitude, location.latitude)
            maxLatitude = max(maxLatitude, location.latitude)
            minLongitude = min(minLongitude, location.longitude)
            maxLongitude = max(maxLongitude, location.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2,
                                            longitude: (minLongitude + maxLongitude) / 2)
        let span = MKCoordinateSpan(latitudeDelta: min(max((maxLatitude - minLatitude) * 1.3, 0.02), 170),
                                    longitudeDelta: min(max((maxLongitude - minLongitude) * 1.3, 0.02), 350))
        mapView.setRegion(mapView.regionThatFits(MKCoordinateRegion(center: center, span: span)),
                          animated: false)
    }

    private func rebuildClusters() {
        cell = MapClustering.cellSize(for: mapView.region.span)
        let fresh = MapClustering.clusters(for: locations, in: mapView.region, cell: cell)

        var next: [Int64: PhotoCluster] = [:]
        var additions: [PhotoCluster] = []
        next.reserveCapacity(fresh.count)
        for (key, cluster) in fresh {
            if let existing = displayed[key], existing.count == cluster.count {
                next[key] = existing
            } else {
                next[key] = cluster
                additions.append(cluster)
            }
        }

        var removals: [PhotoCluster] = []
        for (key, existing) in displayed where next[key] !== existing {
            removals.append(existing)
        }

        displayed = next
        mapView.removeAnnotations(removals)
        mapView.addAnnotations(additions)
    }

    private func members(of cluster: PhotoCluster) -> [PhotoLocation] {
        return locations.filter {
            MapClustering.key(latitude: $0.latitude, longitude: $0.longitude, cell: cell) == cluster.key
        }
    }

    private func openBucket(with photos: [Photo]) {
        guard !photos.isEmpty else { return }
        present(PhotoBucketViewController(services: services, photos: photos),
                animated: true,
                completion: nil)
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
}

extension MapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard !locations.isEmpty else { return }
        rebuildClusters()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let cluster = annotation as? PhotoCluster else { return nil }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: PhotoMarkerView.reuseIdentifier,
                                                         for: annotation) as! PhotoMarkerView
        view.configure(with: cluster, loader: services.images)
        return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        mapView.deselectAnnotation(view.annotation, animated: false)
        guard let cluster = view.annotation as? PhotoCluster else { return }

        guard cluster.count > 1 else {
            openBucket(with: [cluster.photo])
            return
        }
        openBucket(with: members(of: cluster).map { $0.photo })
    }
}
