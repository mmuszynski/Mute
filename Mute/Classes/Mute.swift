//
//  Mute.swift
//  Mute
//
//  Created by Akram Hussein on 08/09/2017.
//

import Foundation
import AudioToolbox
import UIKit

@objcMembers
public class Mute: NSObject {

    public typealias MuteNotificationCompletion = ((_ mute: Bool) -> Void)

    /// A state describing the position of the mute switch
    ///
    /// Created because the asynchronous versions are able to return a value, and that value may be more descriptive than the Boolean `isMute`
    public enum MuteState {
        case muted
        case notMuted
        case unknown
    }
    
    // MARK: Properties

    /// Shared instance
    public static let shared = Mute()

    /// Sound ID for mute sound
    private let soundUrl = Mute.muteSoundUrl

    /// Should notify every second or only when changes?
    /// True will notify every second of the state, false only when it changes
    public var alwaysNotify = true

    /// Notification handler to be triggered when mute status changes
    /// Triggered every second if alwaysNotify=true, otherwise only when it switches state
    public var notify: MuteNotificationCompletion?

    /// Currently playing? used when returning from the background (if went to background and foreground really quickly)
    public private(set) var isPlaying = false

    /// Current mute state as a `MuteState`
    public private(set) var switchState: MuteState = .unknown
    
    /// Current mute state
    @available(*, unavailable, renamed: "isMuted")
    public private(set) var isMute = false
    
    /// Returns true if the current state is `muted` and false if the current state is `notMuted` or `unknown`
    public var isMuted: Bool { return switchState == .muted }

    /// Sound is scheduled
    private var isScheduled = false

    /// State of detection - paused when in background
    public var isPaused = false {
        didSet {
            if !self.isPaused && oldValue && !self.isPlaying {
                self.schedulePlaySound()
            }
        }
    }

    /// How frequently to check (seconds), minimum = 0.5
    public var checkInterval = 1.0 {
        didSet {
            if self.checkInterval < 0.5 {
                print("MUTE: checkInterval cannot be less than 0.5s, setting to 0.5")
                self.checkInterval = 0.5
            }
        }
    }

    /// Silent sound (0.5 sec)
    private var soundId: SystemSoundID = 0

    /// Time difference between start and finish of mute sound
    private var interval: TimeInterval = 0

    // MARK: Resources

    /// Library bundle
    private static var bundle: Bundle {
        if let path = Bundle(for: Mute.self).path(forResource: "Mute", ofType: "bundle"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let spmBundleName = "Mute_Mute"

        let candidates = [
            // Bundle should be present here when the package is linked into an App.
            Bundle.main.resourceURL,

            // Bundle should be present here when the package is linked into a framework.
            Bundle(for: Mute.self).resourceURL
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(spmBundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }

        fatalError("Mute.bundle not found")
    }

    /// Mute sound url path
    private static var muteSoundUrl: URL {
        guard let muteSoundUrl = Mute.bundle.url(forResource: "mute", withExtension: "aiff") else {
            fatalError("mute.aiff not found")
        }
        return muteSoundUrl
    }

    // MARK: Init

    /// private init
    private override init() {
        super.init()

        self.soundId = 1

        if AudioServicesCreateSystemSoundID(self.soundUrl as CFURL, &self.soundId) == kAudioServicesNoError {
            var yes: UInt32 = 1
            AudioServicesSetProperty(kAudioServicesPropertyIsUISound,
                                     UInt32(MemoryLayout.size(ofValue: self.soundId)),
                                     &self.soundId,
                                     UInt32(MemoryLayout.size(ofValue: yes)),
                                     &yes)

            self.schedulePlaySound()
        } else {
            print("Failed to setup sound player")
            self.soundId = 0
        }

        // Notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(Mute.didEnterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(Mute.willEnterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    deinit {
        if self.soundId != 0 {
            AudioServicesRemoveSystemSoundCompletion(self.soundId)
            AudioServicesDisposeSystemSoundID(self.soundId)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Notification Handlers

    /// Selector called when app enters background
    @objc private func didEnterBackground(_ sender: Any) {
        self.isPaused = true
    }

    /// Selector called when app will enter foreground
    @objc private func willEnterForeground(_ sender: Any) {
        self.isPaused = false
    }

    // MARK: Methods

    /// Starts a mute check outside the `checkInterval`
    public func check() {
        self.playSound()
    }

    /// Schedules mute sound to be played at `checkInterval`
    private func schedulePlaySound() {
        /// Don't schedule a new one if we already have one queued
        if self.isScheduled { return }

        self.isScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + self.checkInterval) {
            self.isScheduled = false

            /// Don't play if we're paused
            if self.isPaused {
                return
            }

            self.playSound()
        }
    }

    /// If not paused, playes mute sound
    private func playSound() {
        if !self.isPaused && !self.isPlaying {
            self.interval = Date.timeIntervalSinceReferenceDate
            self.isPlaying = true
            AudioServicesPlaySystemSoundWithCompletion(self.soundId) { [weak self] in
                self?.soundFinishedPlaying()
            }
        }
    }

    /// Called when AudioService finished playing sound
    private func soundFinishedPlaying() {
        self.isPlaying = false

        let elapsed = Date.timeIntervalSinceReferenceDate - self.interval
        let isMute = elapsed < 0.1

        if self.isMuted != isMute || self.alwaysNotify {
            self.switchState = isMute ? .muted : .notMuted
            DispatchQueue.main.async {
                self.notify?(isMute)
            }
        }
        self.schedulePlaySound()
    }
    
    
    /*
    ====================
    Async/Await versions
    ====================
    */
    
    @available(iOS 13.0.0, *)
    @MainActor
    /// Checks for the position of the mute switch asynchronously
    public func checkMuteAsynchronously() async -> MuteState {
        return await self.playSoundAsynchronously()
    }
    
    @available(iOS 13.0.0, *)
    private func playSoundAsynchronously() async -> MuteState {
        return await withCheckedContinuation { continuation in
            if !self.isPaused && !self.isPlaying {
                self.interval = Date.timeIntervalSinceReferenceDate
                self.isPlaying = true
                
                AudioServicesPlaySystemSoundWithCompletion(self.soundId) {
                    self.isPlaying = false

                    let elapsed = Date.timeIntervalSinceReferenceDate - self.interval
                    let isMute = elapsed < 0.1

                    if self.isMuted != isMute || self.alwaysNotify {
                        continuation.resume(returning: isMute ? .muted : .notMuted)
                    }
                }
            }
        }
    }
}
