//
//  HUDView.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

// MARK: - HUDType

enum HUDType {
    case volume
    case brightness
}

// MARK: - HUDStyle

enum HUDStyle: String {
    case classic
    case modern

    static let preferenceKey = "hudStyle"

    static var current: HUDStyle {
        HUDStyle(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .modern
    }

    var windowPadding: CGFloat { self == .modern ? 24 : 0 }
    var windowSize: CGFloat { 200 + windowPadding * 2 }
}

// MARK: - HUDView

struct HUDView: View {
    let hudType: HUDType
    let value: Float
    let isMuted: Bool
    var style: HUDStyle = .modern

    var body: some View {
        switch style {
        case .classic:
            ClassicHUDView(hudType: hudType, value: value, isMuted: isMuted)
        case .modern:
            ModernHUDView(hudType: hudType, value: value, isMuted: isMuted)
        }
    }
}

#Preview("Volume") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .volume, value: 0.7, isMuted: false)
    }
}

#Preview("Mute") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .volume, value: 0.0, isMuted: true)
    }
}

#Preview("Brightness") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .brightness, value: 0.5, isMuted: false)
    }
}
