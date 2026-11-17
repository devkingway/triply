import SwiftUI
import CoreText
import UIKit

/// Triply's typeface: Poppins (SIL Open Font License, see Fonts/Poppins-OFL.txt).
/// Fonts ship inside each target (app, widget, share sheet) and are registered at launch.
enum AppFont {
    private static var registered = false

    /// Makes the bundled Poppins files available. Safe to call more than once.
    static func register() {
        guard !registered else { return }
        registered = true
        for face in ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"] {
            guard let url = Bundle.main.url(forResource: "Poppins-\(face)", withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The Poppins file to use for a weight (Poppins has no separate light/black files here).
    static func faceName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Poppins-Medium"
        case .semibold: "Poppins-SemiBold"
        case .bold: "Poppins-Bold"
        case .heavy, .black: "Poppins-ExtraBold"
        default: "Poppins-Regular"
        }
    }

    /// Poppins runs a little larger than the iPhone font at the same size, so sizes are trimmed slightly
    /// to keep the existing layouts fitting.
    static let sizeScale: CGFloat = 0.94

    /// Navigation bar titles and the Plan/Budget/Flights/Hotels switch are drawn by iOS: style them too.
    static func styleSystemControls() {
        let title = UIFont(name: "Poppins-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let large = UIFont(name: "Poppins-Bold", size: 32) ?? .systemFont(ofSize: 34, weight: .bold)
        UINavigationBar.appearance().titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        let segment = UIFont(name: "Poppins-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        let segmentSelected = UIFont(name: "Poppins-SemiBold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segment], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentSelected], for: .selected)
    }
}

extension Font.TextStyle {
    /// iPhone's default point size for each text style (grows with the user's text size setting).
    var defaultSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    /// The weight the iPhone uses for this style by default (headline is semibold).
    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

extension Font {
    /// Poppins in an iPhone text style, e.g. `.app(.caption, .semibold)`. Scales with Dynamic Type.
    static func app(_ style: TextStyle, _ weight: Weight? = nil) -> Font {
        .custom(AppFont.faceName(for: weight ?? style.defaultWeight),
                size: style.defaultSize * AppFont.sizeScale,
                relativeTo: style)
    }

    /// Poppins at a fixed size (badges, big icons and numbers).
    static func poppins(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(AppFont.faceName(for: weight), fixedSize: size * AppFont.sizeScale)
    }
}
