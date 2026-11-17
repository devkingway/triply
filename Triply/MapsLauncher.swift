import SwiftUI
import MapKit
import UIKit

/// Map apps offered when opening directions.
enum MapApp: String, CaseIterable, Identifiable {
    case apple, google, naver, amap
    var id: String { rawValue }

    var name: String {
        switch self {
        case .apple: "Apple Maps"
        case .google: "Google Maps"
        case .naver: "Naver Map"
        case .amap: "Amap (高德地图)"
        }
    }
}

enum TravelChoice {
    case walk, transit, drive

    var label: String {
        switch self {
        case .walk: "Walk"
        case .transit: "Transit"
        case .drive: "Drive"
        }
    }
}

/// Where to get directions to, waiting for the user to pick a map app.
struct DirectionsRequest: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let mode: TravelChoice
}

/// Opens directions in the chosen map app. If the app isn't installed, falls back to its website
/// (Google Maps, Amap) or App Store page (Naver Map).
enum MapsLauncher {
    @MainActor
    static func open(_ app: MapApp, _ request: DirectionsRequest) {
        let lat = request.coordinate.latitude
        let lon = request.coordinate.longitude
        let name = request.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        switch app {
        case .apple:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: request.coordinate))
            item.name = request.name
            let mode = switch request.mode {
            case .walk: MKLaunchOptionsDirectionsModeWalking
            case .transit: MKLaunchOptionsDirectionsModeTransit
            case .drive: MKLaunchOptionsDirectionsModeDriving
            }
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])

        case .google:
            let mode = switch request.mode {
            case .walk: "walking"
            case .transit: "transit"
            case .drive: "driving"
            }
            launch(app: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=\(mode)",
                   fallback: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)&travelmode=\(mode)")

        case .naver:
            let mode = switch request.mode {
            case .walk: "walk"
            case .transit: "public"
            case .drive: "car"
            }
            launch(app: "nmap://route/\(mode)?dlat=\(lat)&dlng=\(lon)&dname=\(name)&appname=com.kingway.tripple",
                   fallback: "https://apps.apple.com/app/id311867728")

        case .amap:
            // t: 0 drive, 1 transit, 2 walk. Coordinates from Apple Maps in China already use Amap's system.
            let t = switch request.mode {
            case .walk: 2
            case .transit: 1
            case .drive: 0
            }
            let webMode = switch request.mode {
            case .walk: "walk"
            case .transit: "bus"
            case .drive: "car"
            }
            launch(app: "iosamap://path?sourceApplication=Triply&dlat=\(lat)&dlon=\(lon)&dname=\(name)&dev=0&t=\(t)",
                   fallback: "https://uri.amap.com/navigation?to=\(lon),\(lat),\(name)&mode=\(webMode)&src=Triply")
        }
    }

    @MainActor
    private static func launch(app: String, fallback: String) {
        if let url = URL(string: app), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: fallback) {
            UIApplication.shared.open(url)
        }
    }
}

extension View {
    /// Centered pop-up asking which map app to open directions in.
    func mapAppChooser(_ request: Binding<DirectionsRequest?>) -> some View {
        alert("Open directions in…",
              isPresented: Binding(get: { request.wrappedValue != nil },
                                   set: { if !$0 { request.wrappedValue = nil } }),
              presenting: request.wrappedValue) { req in
            ForEach(MapApp.allCases) { app in
                Button(app.name) { MapsLauncher.open(app, req) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { req in
            Text("\(req.mode.label) to \(req.name)")
        }
    }
}
