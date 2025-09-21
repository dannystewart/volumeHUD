//
//  ContentView.swift
//  Volume HUD
//
//  Created by Danny Stewart on 9/21/25.
//

import Combine
import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var volumeMonitor = VolumeMonitor()
    @StateObject private var hudController = HUDController()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Volume HUD")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Press volume keys to see the HUD overlay")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Volume: \(Int(volumeMonitor.currentVolume * 100))%")
                Text("Is Muted: \(volumeMonitor.isMuted ? "Yes" : "No")")
                Text("HUD Active: \(hudController.isShowing ? "Yes" : "No")")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Button("Test HUD") {
                hudController.showVolumeHUD(volume: volumeMonitor.currentVolume, isMuted: volumeMonitor.isMuted)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: 400, maxHeight: 300)
        .onAppear {
            volumeMonitor.startMonitoring()
            hudController.volumeMonitor = volumeMonitor
            volumeMonitor.hudController = hudController
        }
        .onDisappear {
            volumeMonitor.stopMonitoring()
        }
    }
}

#Preview {
    ContentView()
}
