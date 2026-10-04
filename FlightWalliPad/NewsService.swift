import Foundation

enum NewsService {
    static func fetchHeadlines() async throws -> [String] {
        let url = URL(string: "https://feeds.bbci.co.uk/news/rss.xml")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Homeboard/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let parser = RSSHeadlineParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        _ = xmlParser.parse()
        return Array(parser.titles.dropFirst().prefix(12))
    }
}

private final class RSSHeadlineParser: NSObject, XMLParserDelegate {
    var titles: [String] = []
    private var inTitle = false
    private var currentTitle = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "title" { inTitle = true; currentTitle = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { currentTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "title" else { return }
        inTitle = false
        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { titles.append(title) }
    }
}
