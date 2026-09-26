import Foundation
import CoreLocation

// MARK: - Cinema via OpenStreetMap Overpass (porting di cinemas.ts)

struct Cinema: Identifiable, Equatable {
    var id: String
    var name: String
    var website: String?
    var address: String?
    var lat: Double?
    var lon: Double?
    var distanceKm: Double?
}

enum CinemasService {
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    private struct OverpassResp: Decodable {
        var elements: [Element]?
    }
    private struct Element: Decodable {
        var type: String
        var id: Int
        var lat: Double?
        var lon: Double?
        var center: Center?
        var tags: [String: String]?
        struct Center: Decodable { var lat: Double; var lon: Double }
    }

    private static func overpassQuery(_ query: String) async throws -> [Element] {
        var lastError: Error?
        for endpoint in endpoints {
            do {
                var req = URLRequest(url: URL(string: endpoint)!)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)".data(using: .utf8)
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return try JSONDecoder().decode(OverpassResp.self, from: data).elements ?? []
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private static func parse(_ elements: [Element]) -> [Cinema] {
        var seen = Set<String>()
        var out: [Cinema] = []
        for el in elements {
            guard let name = el.tags?["name"] else { continue }
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }

            var parts: [String] = []
            if let street = el.tags?["addr:street"] {
                let num = el.tags?["addr:housenumber"]
                parts.append(street + (num.map { " \($0)" } ?? ""))
            }
            if let city = el.tags?["addr:city"] { parts.append(city) }

            out.append(Cinema(
                id: "\(el.type)/\(el.id)",
                name: name,
                website: el.tags?["website"] ?? el.tags?["contact:website"],
                address: parts.isEmpty ? nil : parts.joined(separator: ", "),
                lat: el.lat ?? el.center?.lat,
                lon: el.lon ?? el.center?.lon,
                distanceKm: nil
            ))
        }
        return out
    }

    /// Cinema della città scelta, ordinati per nome.
    static func fetchByCity(_ cityName: String) async throws -> [Cinema] {
        let city = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { return [] }
        let escaped = city.replacingOccurrences(of: "\"", with: "\\\"")
        let query = """
        [out:json][timeout:25];
        area["name"="\(escaped)"]["boundary"="administrative"]->.a;
        (
          nwr["amenity"="cinema"](area.a);
        );
        out center tags;
        """
        let cinemas = parse(try await overpassQuery(query))
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return cinemas
    }

    /// Cinema in un raggio (default 15 km) ordinati per distanza.
    static func fetchNearby(latitude: Double, longitude: Double, radiusMeters: Double = 15_000) async throws -> [Cinema] {
        let dLat = radiusMeters / 111_320
        let dLon = radiusMeters / (111_320 * max(0.2, cos(latitude * .pi / 180)))
        let bbox = String(format: "%.5f,%.5f,%.5f,%.5f",
                          latitude - dLat, longitude - dLon, latitude + dLat, longitude + dLon)
        let query = """
        [out:json][timeout:25];
        (
          nwr["amenity"="cinema"](\(bbox));
        );
        out center tags;
        """
        var cinemas = parse(try await overpassQuery(query))
        for i in cinemas.indices {
            if let lat = cinemas[i].lat, let lon = cinemas[i].lon {
                cinemas[i].distanceKm = haversineKm(lat1: latitude, lon1: longitude, lat2: lat, lon2: lon)
            }
        }
        cinemas.sort { a, b in
            let da = a.distanceKm ?? .infinity
            let db = b.distanceKm ?? .infinity
            if da != db { return da < db }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
        return cinemas
    }

    /// Posizione corrente (se il permesso è concesso), null altrimenti.
    static func currentLocation() async -> CLLocation? {
        final class Delegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
            let cont: CheckedContinuation<CLLocation?, Never>
            init(_ cont: CheckedContinuation<CLLocation?, Never>) { self.cont = cont }
            func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
                cont.resume(returning: locations.last)
            }
            func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
                cont.resume(returning: nil)
            }
        }
        let locator = CLLocationManager()
        locator.requestWhenInUseAuthorization()
        return await withCheckedContinuation { cont in
            let delegate = Delegate(cont)
            locator.delegate = delegate
            locator.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locator.requestLocation()
        }
    }

    /// Nome della città dalle coordinate (reverse geocoding di sistema).
    static func cityFromLocation(_ loc: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let places = try? await geocoder.reverseGeocodeLocation(loc) else { return nil }
        return places.compactMap(\.locality).first
    }

    static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(a))
    }

    // MARK: Link di prenotazione

    private static let chainDirect: [(match: String, url: (String, String) -> String)] = [
        ("the\\s*space|uci\\s*cinemas", { m, c in
            "https://www.thespacecinema.it/\(c.isEmpty ? "movies?" : "movies?city=\(c)&")q=\(m)"
        }),
    ]

    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    /// Costruisce il link di prenotazione per il cinema scelto.
    static func bookingUrl(cinema: Cinema, movieTitle: String, cityName: String?) -> (url: String, direct: Bool) {
        let m = movieTitle.trimmingCharacters(in: .whitespaces)
        let c = (cityName ?? "").trimmingCharacters(in: .whitespaces)

        // 1. Catena con sito proprio
        for chain in chainDirect {
            if cinema.name.range(of: chain.match, options: [.regularExpression, .caseInsensitive]) != nil {
                return (chain.url(urlEncode(m), urlEncode(c)), true)
            }
        }

        // 2. Cinema con sito proprio: ricerca sul dominio
        if let website = cinema.website, !website.isEmpty {
            let base = website.hasPrefix("http") ? website : "https://\(website)"
            let host = URL(string: base)?.host ?? base
            return ("https://www.google.com/search?q=\(urlEncode("site:\(host) \(m) biglietti"))", false)
        }

        // 3. Piattaforme nazionali
        if !c.isEmpty {
            return ("https://www.l-id.it/it/events?search=\(urlEncode(m))&city=\(urlEncode(c))", true)
        }
        return ("https://www.google.com/search?q=\(urlEncode("biglietti \(m) cinema \(c.isEmpty ? "Italia" : c)"))", false)
    }

    /// Prenotazione rapida per città (dai chip).
    static func quickBookingUrl(city: String, movieTitle: String) -> (url: String, direct: Bool) {
        let m = movieTitle.trimmingCharacters(in: .whitespaces)
        let c = city.trimmingCharacters(in: .whitespaces)
        if c.isEmpty {
            return ("https://www.google.com/search?q=\(urlEncode("biglietti \(m) cinema Italia"))", false)
        }
        return ("https://www.l-id.it/it/events?search=\(urlEncode(m))&city=\(urlEncode(c))", true)
    }
}
