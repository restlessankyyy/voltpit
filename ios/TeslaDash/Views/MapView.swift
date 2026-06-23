import SwiftUI
import MapKit

/// An Apple MapKit map that mirrors the Tesla / Apple driver-display navigation
/// view: a dark 3D-tilted map that rotates so travel is always "up", with a
/// blue navigation chevron puck. Uses MapKit so it needs no API key or billing.
struct MapView: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D?
    var heading: Double?
    var moving: Bool

    private static let defaultCenter = CLLocationCoordinate2D(latitude: 37.7766, longitude: -122.4172)
    // Tight, steep camera so buildings rise up for a street-level 3D feel.
    private static let cameraDistance: CLLocationDistance = 320
    private static let pitch: CGFloat = 60

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark

        // Standard map with 3D buildings and muted points of interest for a
        // clean turn-by-turn look.
        let config = MKStandardMapConfiguration(elevationStyle: .realistic,
                                                emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config

        map.showsUserLocation = false
        map.showsCompass = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isZoomEnabled = true
        map.isScrollEnabled = true

        let start = coordinate ?? Self.defaultCenter
        let marker = CarAnnotation(coordinate: start)
        map.addAnnotation(marker)
        context.coordinator.marker = marker

        let camera = MKMapCamera(
            lookingAtCenter: start,
            fromDistance: Self.cameraDistance,
            pitch: Self.pitch,
            heading: heading ?? 0
        )
        map.setCamera(camera, animated: false)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard let coordinate else { return }

        // Move the puck to the new position.
        if let marker = context.coordinator.marker {
            marker.coordinate = coordinate
        }

        let bearing = moving ? (heading ?? map.camera.heading) : map.camera.heading

        // Follow the car but keep whatever zoom (camera distance) the driver
        // pinched to, so manual zoom/pan to inspect streets is never reset.
        let camera = MKMapCamera(
            lookingAtCenter: coordinate,
            fromDistance: map.camera.centerCoordinateDistance,
            pitch: map.camera.pitch,
            heading: bearing
        )
        map.setCamera(camera, animated: true)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var marker: CarAnnotation?

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is CarAnnotation else { return nil }
            let id = "car"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.image = MapView.navChevron
            view.centerOffset = .zero
            return view
        }
    }

    final class CarAnnotation: NSObject, MKAnnotation {
        @objc dynamic var coordinate: CLLocationCoordinate2D
        init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    }

    /// A turn-by-turn navigation chevron: a blue arrowhead pointing "up"
    /// (forward) inside a soft white-rimmed disc.
    static let navChevron: UIImage = makeNavChevron()

    private static func makeNavChevron() -> UIImage {
        let size = CGSize(width: 60, height: 60)
        let mid = size.width / 2
        let center = CGPoint(x: mid, y: mid)
        let navBlue = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext

            // --- White disc base with a soft drop shadow ---
            let discRadius: CGFloat = 22
            let disc = UIBezierPath(arcCenter: center, radius: discRadius,
                                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 6,
                        color: UIColor.black.withAlphaComponent(0.30).cgColor)
            UIColor.white.setFill()
            disc.fill()
            c.restoreGState()

            // --- Blue navigation chevron / arrowhead pointing up ---
            let chevron = UIBezierPath()
            chevron.move(to: CGPoint(x: mid, y: mid - 14))          // tip
            chevron.addLine(to: CGPoint(x: mid + 11, y: mid + 13))  // bottom-right
            chevron.addQuadCurve(to: CGPoint(x: mid - 11, y: mid + 13), // bottom-left
                                 controlPoint: CGPoint(x: mid, y: mid + 6)) // notch
            chevron.close()
            navBlue.setFill()
            chevron.fill()
        }
    }
}
