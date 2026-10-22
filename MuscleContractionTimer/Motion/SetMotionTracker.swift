//
//  SetMotionTracker.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/20/26.
//

import Foundation
import CoreMotion
import Combine

@MainActor
public final class SetMotionTracker: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    public static let shared = SetMotionTracker()
    
    @Published public var selectedSource: SensorSource = .iPhone {
        didSet {
            if selectedSource == .airPods {
                AudioHandoffManager.shared.triggerAirPodsHandoff()
            }
        }
    }
    @Published public var phaseOrder: ExercisePhaseOrder = .eccentricFirst
    @Published public private(set) var activeSetID: UUID?
    @Published public private(set) var isAirPodsConnected: Bool = false
    
    private weak var activeSet: ExerciseSet?
    private let iPhoneManager = CMMotionManager()
    private let headphoneManager = CMHeadphoneMotionManager()
    private let activityManager = CMMotionActivityManager()
    
    private var recordedFrames: [RawMotionFrame] = []
    private var currentTrackingSource: SensorSource = .iPhone
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.musclecontractiontimer.setrowqueue"
        q.qualityOfService = .userInteractive
        return q
    }()
    
    private override init() {
        super.init()
        iPhoneManager.deviceMotionUpdateInterval = 1.0 / 100.0
        headphoneManager.delegate = self
        isAirPodsConnected = headphoneManager.isDeviceMotionAvailable
        requestPermissionsIfNeeded()
    }
    
    func beginTracking(for set: ExerciseSet) {
        // If another set row is currently recording, finish and analyze it first
        if let current = activeSet, current.id != set.id, current.state == .started {
            current.cycleState()
        }
        
        stopHardwareUpdates()
        recordedFrames.removeAll()
        recordedFrames.reserveCapacity(6000)
        
        activeSet = set
        activeSetID = set.id
        
        var sourceToUse: SensorSource = selectedSource
        
        switch sourceToUse {
        case .airPods:
            AudioHandoffManager.shared.triggerAirPodsHandoff()
            if headphoneManager.isDeviceMotionAvailable {
                currentTrackingSource = .airPods
                AudioHandoffManager.shared.playActionCue()
                headphoneManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
                    guard let motion = motion, error == nil else { return }
                    let frame = RawMotionFrame(from: motion)
                    Task { @MainActor [weak self] in
                        self?.recordedFrames.append(frame)
                    }
                }
                return
            }
            // Fall back to iPhone if headphone motion is unavailable
            sourceToUse = .iPhone
            fallthrough
            
        case .iPhone:
            currentTrackingSource = .iPhone
            guard iPhoneManager.isDeviceMotionAvailable else { return }
            AudioHandoffManager.shared.playActionCue()
            iPhoneManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
                guard let motion = motion, error == nil else { return }
                let frame = RawMotionFrame(from: motion)
                Task { @MainActor [weak self] in
                    self?.recordedFrames.append(frame)
                }
            }
        }
    }
    
    func finishTracking(for set: ExerciseSet) {
        guard activeSetID == set.id else { return }
        stopHardwareUpdates()
        AudioHandoffManager.shared.playActionCue()
        
        let framesSnapshot = recordedFrames
        let sourceSnapshot = currentTrackingSource
        let orderSnapshot = phaseOrder
        
        activeSet = nil
        activeSetID = nil
        recordedFrames.removeAll()
        
        set.storeAndAnalyze(
            frames: framesSnapshot,
            source: sourceSnapshot,
            phaseOrder: orderSnapshot
        )
    }
    
    func cancelTracking(for set: ExerciseSet) {
        if activeSetID == set.id {
            stopHardwareUpdates()
            activeSet = nil
            activeSetID = nil
            recordedFrames.removeAll()
        }
    }
    
    private func stopHardwareUpdates() {
        iPhoneManager.stopDeviceMotionUpdates()
        headphoneManager.stopDeviceMotionUpdates()
    }
    
    private func requestPermissionsIfNeeded() {
        if CMMotionActivityManager.authorizationStatus() == .notDetermined {
            let now = Date()
            activityManager.queryActivityStarting(from: now, to: now, to: .main) { _, _ in }
        }
    }
    
    nonisolated public func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.isAirPodsConnected = true }
    }
    
    nonisolated public func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.isAirPodsConnected = false }
    }
}
