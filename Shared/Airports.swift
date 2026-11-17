import Foundation

struct Airport {
    let code: String
    let city: String
    let timeZone: String
}

/// A small built-in list of common airports so flight times show in each airport's local time.
/// Codes not in the list fall back to the phone's time zone.
enum Airports {
    static let all: [Airport] = [
        // Malaysia
        Airport(code: "KUL", city: "Kuala Lumpur", timeZone: "Asia/Kuala_Lumpur"),
        Airport(code: "SZB", city: "Subang", timeZone: "Asia/Kuala_Lumpur"),
        Airport(code: "PEN", city: "Penang", timeZone: "Asia/Kuala_Lumpur"),
        Airport(code: "LGK", city: "Langkawi", timeZone: "Asia/Kuala_Lumpur"),
        Airport(code: "JHB", city: "Johor Bahru", timeZone: "Asia/Kuala_Lumpur"),
        Airport(code: "BKI", city: "Kota Kinabalu", timeZone: "Asia/Kuching"),
        Airport(code: "KCH", city: "Kuching", timeZone: "Asia/Kuching"),
        Airport(code: "MYY", city: "Miri", timeZone: "Asia/Kuching"),
        Airport(code: "KBR", city: "Kota Bharu", timeZone: "Asia/Kuala_Lumpur"),
        Airport(code: "TGG", city: "Kuala Terengganu", timeZone: "Asia/Kuala_Lumpur"),
        // Southeast Asia
        Airport(code: "SIN", city: "Singapore", timeZone: "Asia/Singapore"),
        Airport(code: "BKK", city: "Bangkok", timeZone: "Asia/Bangkok"),
        Airport(code: "DMK", city: "Bangkok Don Mueang", timeZone: "Asia/Bangkok"),
        Airport(code: "HKT", city: "Phuket", timeZone: "Asia/Bangkok"),
        Airport(code: "CNX", city: "Chiang Mai", timeZone: "Asia/Bangkok"),
        Airport(code: "KBV", city: "Krabi", timeZone: "Asia/Bangkok"),
        Airport(code: "CGK", city: "Jakarta", timeZone: "Asia/Jakarta"),
        Airport(code: "DPS", city: "Bali", timeZone: "Asia/Makassar"),
        Airport(code: "MNL", city: "Manila", timeZone: "Asia/Manila"),
        Airport(code: "CEB", city: "Cebu", timeZone: "Asia/Manila"),
        Airport(code: "SGN", city: "Ho Chi Minh City", timeZone: "Asia/Ho_Chi_Minh"),
        Airport(code: "HAN", city: "Hanoi", timeZone: "Asia/Ho_Chi_Minh"),
        Airport(code: "DAD", city: "Da Nang", timeZone: "Asia/Ho_Chi_Minh"),
        Airport(code: "PNH", city: "Phnom Penh", timeZone: "Asia/Phnom_Penh"),
        Airport(code: "REP", city: "Siem Reap", timeZone: "Asia/Phnom_Penh"),
        // East Asia
        Airport(code: "HKG", city: "Hong Kong", timeZone: "Asia/Hong_Kong"),
        Airport(code: "MFM", city: "Macau", timeZone: "Asia/Macau"),
        Airport(code: "TPE", city: "Taipei", timeZone: "Asia/Taipei"),
        Airport(code: "ICN", city: "Seoul Incheon", timeZone: "Asia/Seoul"),
        Airport(code: "GMP", city: "Seoul Gimpo", timeZone: "Asia/Seoul"),
        Airport(code: "PUS", city: "Busan", timeZone: "Asia/Seoul"),
        Airport(code: "CJU", city: "Jeju", timeZone: "Asia/Seoul"),
        Airport(code: "NRT", city: "Tokyo Narita", timeZone: "Asia/Tokyo"),
        Airport(code: "HND", city: "Tokyo Haneda", timeZone: "Asia/Tokyo"),
        Airport(code: "KIX", city: "Osaka Kansai", timeZone: "Asia/Tokyo"),
        Airport(code: "CTS", city: "Sapporo", timeZone: "Asia/Tokyo"),
        Airport(code: "FUK", city: "Fukuoka", timeZone: "Asia/Tokyo"),
        Airport(code: "NGO", city: "Nagoya", timeZone: "Asia/Tokyo"),
        Airport(code: "OKA", city: "Okinawa", timeZone: "Asia/Tokyo"),
        Airport(code: "PEK", city: "Beijing", timeZone: "Asia/Shanghai"),
        Airport(code: "PKX", city: "Beijing Daxing", timeZone: "Asia/Shanghai"),
        Airport(code: "PVG", city: "Shanghai Pudong", timeZone: "Asia/Shanghai"),
        Airport(code: "CAN", city: "Guangzhou", timeZone: "Asia/Shanghai"),
        Airport(code: "SZX", city: "Shenzhen", timeZone: "Asia/Shanghai"),
        Airport(code: "CTU", city: "Chengdu", timeZone: "Asia/Shanghai"),
        // South Asia & Middle East
        Airport(code: "DEL", city: "Delhi", timeZone: "Asia/Kolkata"),
        Airport(code: "BOM", city: "Mumbai", timeZone: "Asia/Kolkata"),
        Airport(code: "MAA", city: "Chennai", timeZone: "Asia/Kolkata"),
        Airport(code: "CMB", city: "Colombo", timeZone: "Asia/Colombo"),
        Airport(code: "MLE", city: "Malé", timeZone: "Indian/Maldives"),
        Airport(code: "KTM", city: "Kathmandu", timeZone: "Asia/Kathmandu"),
        Airport(code: "DXB", city: "Dubai", timeZone: "Asia/Dubai"),
        Airport(code: "DOH", city: "Doha", timeZone: "Asia/Qatar"),
        Airport(code: "JED", city: "Jeddah", timeZone: "Asia/Riyadh"),
        Airport(code: "MED", city: "Madinah", timeZone: "Asia/Riyadh"),
        Airport(code: "IST", city: "Istanbul", timeZone: "Europe/Istanbul"),
        // Australia & NZ
        Airport(code: "SYD", city: "Sydney", timeZone: "Australia/Sydney"),
        Airport(code: "MEL", city: "Melbourne", timeZone: "Australia/Melbourne"),
        Airport(code: "PER", city: "Perth", timeZone: "Australia/Perth"),
        Airport(code: "BNE", city: "Brisbane", timeZone: "Australia/Brisbane"),
        Airport(code: "AKL", city: "Auckland", timeZone: "Pacific/Auckland"),
        // Europe & Americas
        Airport(code: "LHR", city: "London Heathrow", timeZone: "Europe/London"),
        Airport(code: "CDG", city: "Paris", timeZone: "Europe/Paris"),
        Airport(code: "AMS", city: "Amsterdam", timeZone: "Europe/Amsterdam"),
        Airport(code: "FRA", city: "Frankfurt", timeZone: "Europe/Berlin"),
        Airport(code: "MUC", city: "Munich", timeZone: "Europe/Berlin"),
        Airport(code: "ZRH", city: "Zurich", timeZone: "Europe/Zurich"),
        Airport(code: "FCO", city: "Rome", timeZone: "Europe/Rome"),
        Airport(code: "BCN", city: "Barcelona", timeZone: "Europe/Madrid"),
        Airport(code: "JFK", city: "New York", timeZone: "America/New_York"),
        Airport(code: "LAX", city: "Los Angeles", timeZone: "America/Los_Angeles"),
        Airport(code: "SFO", city: "San Francisco", timeZone: "America/Los_Angeles"),
    ]

    static func find(_ code: String) -> Airport? {
        let upper = code.uppercased()
        return all.first { $0.code == upper }
    }

    static func timeZone(for code: String) -> TimeZone {
        find(code).flatMap { TimeZone(identifier: $0.timeZone) } ?? .current
    }
}
