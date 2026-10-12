import Foundation

/// The seven UAE emirates we ship official Awqaf static data for. Each case maps to
/// a per-emirate folder under `prayer_times/<year>/<slug>/` and to the Awqaf API IDs the
/// data was fetched with. The centroid coordinates drive "nearest emirate" detection
/// when CoreLocation reports the user is inside the UAE.
enum Emirate: String, CaseIterable, Codable, Identifiable, Hashable {
    case abudhabi
    case dubai
    case sharjah
    case ajman
    case ummalquwain
    case rasalkhaimah
    case fujairah

    var id: String { rawValue }
    var slug: String { rawValue }

    var nameEn: String {
        switch self {
        case .abudhabi: return "Abu Dhabi"
        case .dubai: return "Dubai"
        case .sharjah: return "Sharjah"
        case .ajman: return "Ajman"
        case .ummalquwain: return "Umm Al Quwain"
        case .rasalkhaimah: return "Ras Al Khaimah"
        case .fujairah: return "Fujairah"
        }
    }

    var nameAr: String {
        switch self {
        case .abudhabi: return "أبوظبي"
        case .dubai: return "دبي"
        case .sharjah: return "الشارقة"
        case .ajman: return "عجمان"
        case .ummalquwain: return "أم القيوين"
        case .rasalkhaimah: return "رأس الخيمة"
        case .fujairah: return "الفجيرة"
        }
    }

    /// Awqaf API IDs the bundled data was fetched with (emirateID/areaID of the capital area).
    var awqafEmirateID: Int {
        switch self {
        case .abudhabi: return 1
        case .dubai: return 2
        case .sharjah: return 3
        case .ajman: return 4
        case .ummalquwain: return 5
        case .rasalkhaimah: return 6
        case .fujairah: return 7
        }
    }

    var awqafAreaID: Int {
        switch self {
        case .abudhabi: return 1
        case .dubai: return 32
        case .sharjah: return 33
        case .ajman: return 41
        case .ummalquwain: return 44
        case .rasalkhaimah: return 45
        case .fujairah: return 52
        }
    }

    /// Approximate centroid (capital city) latitude/longitude, for nearest-emirate matching.
    var latitude: Double {
        switch self {
        case .abudhabi: return 24.4539
        case .dubai: return 25.2048
        case .sharjah: return 25.3463
        case .ajman: return 25.4052
        case .ummalquwain: return 25.5647
        case .rasalkhaimah: return 25.7895
        case .fujairah: return 25.1288
        }
    }

    var longitude: Double {
        switch self {
        case .abudhabi: return 54.3773
        case .dubai: return 55.2708
        case .sharjah: return 55.4209
        case .ajman: return 55.5136
        case .ummalquwain: return 55.6550
        case .rasalkhaimah: return 55.9432
        case .fujairah: return 56.3265
        }
    }

    /// The emirate whose centroid is closest to the given coordinate (great-circle distance).
    static func nearest(toLatitude lat: Double, longitude lon: Double) -> Emirate {
        func haversineKm(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
            let r = 6371.0
            let dLat = (bLat - aLat) * .pi / 180
            let dLon = (bLon - aLon) * .pi / 180
            let s = sin(dLat / 2) * sin(dLat / 2)
                + cos(aLat * .pi / 180) * cos(bLat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
            return r * 2 * atan2(sqrt(s), sqrt(1 - s))
        }
        return allCases.min { a, b in
            haversineKm(lat, lon, a.latitude, a.longitude) < haversineKm(lat, lon, b.latitude, b.longitude)
        } ?? .dubai
    }

    static func from(slug: String?) -> Emirate? {
        guard let slug else { return nil }
        return Emirate(rawValue: slug)
    }
}
