import Foundation

enum BrowserControllerPage {
    static let html: String = {
        guard let url = Bundle.main.url(forResource: "controller", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            return fallback
        }
        return html
    }()

    private static let fallback = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width"></head>
    <body style="font-family:system-ui;background:#08080b;color:white;padding:2rem">
    <h1>Vibe Watch</h1><p>The controller resource is missing. Rebuild Vibe Watch Bridge.</p>
    </body></html>
    """
}
