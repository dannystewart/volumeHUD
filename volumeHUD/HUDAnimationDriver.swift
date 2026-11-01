//
//  HUDAnimationDriver.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import QuartzCore
import SwiftUI

// MARK: - HUDAnimationDriver

/// One main-run-loop clock for every part of a Modern HUD transition.
@MainActor
final class HUDAnimationDriver: NSObject {
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 0
    private var curve: UnitCurve = .linear
    private var update: ((Double) -> Void)?
    private var completion: (() -> Void)?

    func animate(
        on screen: NSScreen,
        duration: TimeInterval,
        curve: UnitCurve,
        update: @escaping (Double) -> Void,
        completion: @escaping () -> Void,
    ) {
        cancel()
        self.duration = duration
        self.curve = curve
        self.update = update
        self.completion = completion
        startTime = CACurrentMediaTime()
        update(0)
        let link = screen.displayLink(target: self, selector: #selector(advance(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        update = nil
        completion = nil
    }

    @objc
    private func advance(_: CADisplayLink) {
        let progress = min(max((CACurrentMediaTime() - startTime) / duration, 0), 1)
        update?(curve.value(at: progress))
        if progress >= 1 {
            let finished = completion
            cancel()
            finished?()
        }
    }
}
