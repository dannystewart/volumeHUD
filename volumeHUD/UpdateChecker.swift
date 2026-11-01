//
//  UpdateChecker.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

#if !SANDBOX
    import Foundation

    enum UpdateChecker {
        private struct Release: Decodable {
            let tag_name: String
        }

        static func isUpdateAvailable() async throws -> Bool {
            let url = URL(string: "https://api.github.com/repos/dannystewart/volumeHUD/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0"
            let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
            let currentComponents = current.split(separator: ".").compactMap { Int($0) }
            for index in 0 ..< max(latestComponents.count, currentComponents.count) {
                let latestPart = index < latestComponents.count ? latestComponents[index] : 0
                let currentPart = index < currentComponents.count ? currentComponents[index] : 0
                if latestPart != currentPart { return latestPart > currentPart }
            }
            return false
        }
    }
#endif
