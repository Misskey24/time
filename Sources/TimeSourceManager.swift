import Foundation

enum TimeSourceManager {
    struct ServerTimeResult {
        let timestampMs: Double
        let latencyMs: Double?
    }

    private static let httpDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        fmt.timeZone = TimeZone(abbreviation: "GMT")
        return fmt
    }()

    static func fetchServerTime(source: TimeSource, completion: @escaping (ServerTimeResult?) -> Void) {
        switch source {
        case .local:
            completion(ServerTimeResult(timestampMs: Date().timeIntervalSince1970 * 1000, latencyMs: 0))
        case .taobao:
            fetchTaobao(completion: completion)
        case .qqMusic:
            fetchQQMusic(completion: completion)
        }
    }

    static func fetchServerTimeMs(source: TimeSource, completion: @escaping (Double?) -> Void) {
        fetchServerTime(source: source) { result in
            completion(result?.timestampMs)
        }
    }

    private static func fetchTaobao(completion: @escaping (ServerTimeResult?) -> Void) {
        let jsonURLs = [
            "https://api.m.taobao.com/rest/api3.do?api=mtop.common.getTimestamp",
            "http://api.m.taobao.com/rest/api3.do?api=mtop.common.getTimestamp",
            "https://acs.m.taobao.com/gw/mtop.common.getTimestamp/1.0/?api=mtop.common.getTimestamp"
        ]
        Self.fetchTaobaoJSON(urlStrings: jsonURLs) { result in
            if let result {
                DispatchQueue.main.async { completion(result) }
                return
            }

            Self.fetchHTTPDate(urlString: "https://www.taobao.com/") { result in
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    private static func fetchTaobaoJSON(urlStrings: [String], completion: @escaping (ServerTimeResult?) -> Void) {
        guard let first = urlStrings.first, let url = URL(string: first) else {
            completion(nil)
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 6)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")

        let sendAt = Date()
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dict = json["data"] as? [String: Any],
               let t = dict["t"] as? String,
               let ms = Double(t) {
                let rttMs = Date().timeIntervalSince(sendAt) * 1000
                completion(ServerTimeResult(timestampMs: ms + rttMs / 2, latencyMs: rttMs))
            } else {
                Self.fetchTaobaoJSON(urlStrings: Array(urlStrings.dropFirst()), completion: completion)
            }
        }.resume()
    }

    private static func fetchHTTPDate(urlString: String, completion: @escaping (ServerTimeResult?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "HEAD"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let sendAt = Date()
        URLSession.shared.dataTask(with: req) { _, response, _ in
            guard let http = response as? HTTPURLResponse,
                  let dateStr = http.value(forHTTPHeaderField: "Date"),
                  let date = Self.httpDateFormatter.date(from: dateStr) else {
                completion(nil)
                return
            }

            let rtt = Date().timeIntervalSince(sendAt)
            let serverMs = date.timeIntervalSince1970 * 1000 + (rtt * 1000) / 2
            completion(ServerTimeResult(timestampMs: serverMs, latencyMs: rtt * 1000))
        }.resume()
    }

    private static func fetchQQMusic(completion: @escaping (ServerTimeResult?) -> Void) {
        guard let url = URL(string: "https://c.y.qq.com/") else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "HEAD"
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let sendAt = Date()
        URLSession.shared.dataTask(with: req) { _, response, _ in
            guard let http = response as? HTTPURLResponse,
                  let dateStr = http.value(forHTTPHeaderField: "Date") else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let date = Self.httpDateFormatter.date(from: dateStr) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let rtt = Date().timeIntervalSince(sendAt)
            let serverMs = date.timeIntervalSince1970 * 1000 + (rtt * 1000) / 2
            DispatchQueue.main.async {
                completion(ServerTimeResult(timestampMs: serverMs, latencyMs: rtt * 1000))
            }
        }.resume()
    }
}
