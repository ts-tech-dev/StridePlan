import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct GPXPoint {
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var time: Date?
    var accuracy: Double
}

/// Minimal GPX 1.1 `<trkpt>` reader. Uses `<hdop>` (× 5 m) as horizontal accuracy when present.
final class GPXParser: NSObject, XMLParserDelegate {
    private var points: [GPXPoint] = []
    private var current: GPXPoint?
    private var text = ""
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(contentsOf url: URL) -> [GPXPoint]? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let delegate = GPXParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.points : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "trkpt",
           let lat = attributeDict["lat"].flatMap(Double.init),
           let lon = attributeDict["lon"].flatMap(Double.init) {
            current = GPXPoint(latitude: lat, longitude: lon, elevation: 0, time: nil, accuracy: 5)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele": current?.elevation = Double(value) ?? 0
        case "time": current?.time = isoFormatter.date(from: value)
        case "hdop": current?.accuracy = (Double(value) ?? 1) * 5
        case "trkpt":
            if let current { points.append(current) }
            current = nil
        default: break
        }
    }
}
