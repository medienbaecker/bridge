import Foundation

public enum Place {
    public static func key(url: String?, app: String) -> String {
        url.flatMap { URL(string: $0)?.host() }.flatMap { $0.isEmpty ? nil : $0 } ?? app
    }

    public static func project(url: String?, window: String?, among projects: [String]) -> String? {
        if let url {
            guard let host = URL(string: url)?.host()?.lowercased(), host.hasSuffix(".test") else { return nil }
            let name = host.dropLast(5).split(separator: ".").last.map(String.init) ?? ""
            return projects.first { $0.lowercased() == name }
        }
        let words = Set((window ?? "").lowercased().split { !($0.isLetter || $0.isNumber || "-_.".contains($0)) }.map(String.init))
        return projects.first { words.contains($0.lowercased()) }
    }
}
