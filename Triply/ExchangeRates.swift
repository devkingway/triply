import Foundation

/// Currencies offered in pickers. MYR (home) first.
enum Currencies {
    static let common = ["MYR", "JPY", "KRW", "THB", "SGD", "IDR", "VND", "PHP", "TWD", "HKD", "CNY",
                         "AUD", "NZD", "USD", "EUR", "GBP", "CHF", "AED", "INR"]

    static func label(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) – \(name)"
    }
}

/// Fetches live exchange rates (no API key needed) and remembers the last ones for offline use.
enum ExchangeRates {
    private static let storeKey = "ratesPerMYR"
    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/MYR")!

    /// Units of each currency per 1 MYR, from the last successful fetch.
    private static var saved: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: storeKey) }
    }

    /// MYR value of one unit of `code`. Tries the internet, falls back to the last saved rate.
    static func rateToMYR(_ code: String) async -> Double? {
        if code == "MYR" { return 1 }
        if let fresh = try? await fetch(), let perMYR = fresh[code], perMYR > 0 {
            return 1 / perMYR
        }
        if let perMYR = saved[code], perMYR > 0 { return 1 / perMYR }
        return nil
    }

    private struct Response: Decodable {
        let result: String
        let rates: [String: Double]
    }

    private static func fetch() async throws -> [String: Double] {
        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result == "success" else { throw URLError(.badServerResponse) }
        saved = response.rates
        return response.rates
    }
}
