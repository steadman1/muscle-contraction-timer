//
//  MotionSessionController.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import Foundation
import CoreMotion
import Combine

@MainActor
public final class MotionSessionController: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    
    public enum SessionState: Equatable {
        case idle
        case recording(frameCount: Int, elapsed: TimeInterval)
        case awaitingRepCount(duration: TimeInterval)
        case analyzing
        case completed
        case error(String)
    }
    
    public enum ManualRepCaptureState: Equatable {
        case idle
        case inFirstPhase(startTime: TimeInterval)
        case inIsometricPause(startTime: TimeInterval, phase1EndTime: TimeInterval)
        case inSecondPhase(startTime: TimeInterval, phase1EndTime: TimeInterval, phase2StartTime: TimeInterval)
    }
    
    @Published public private(set) var state: SessionState = .idle
    @Published public var selectedSource: SensorSource = .iPhone {
        didSet {
            if selectedSource == .airPods {
                AudioHandoffManager.shared.triggerAirPodsHandoff()
            }
        }
    }
    @Published public var phaseOrder: ExercisePhaseOrder = .eccentricFirst {
        didSet {
            if let existing = analysisResult {
                analysisResult = SessionAnalysisResult(
                    source: existing.source,
                    phaseOrder: phaseOrder,
                    principalAxis: existing.principalAxis,
                    explainedVarianceRatio: existing.explainedVarianceRatio,
                    samples: existing.samples,
                    cycles: existing.cycles,
                    groundTruthReps: existing.groundTruthReps
                )
            }
        }
    }
    @Published public var userEnteredRepCount: Int = 8
    @Published public var config: AnalyzerConfiguration = .preset(for: .iPhone)
    @Published public private(set) var analysisResult: SessionAnalysisResult?
    @Published public private(set) var isAirPodsConnected: Bool = false
    @Published public private(set) var hasSavedCurrentSet: Bool = false
    
    @Published public private(set) var manualCaptureState: ManualRepCaptureState = .idle
    @Published public private(set) var manualGroundTruthReps: [GroundTruthRep] = []
    
    private let iPhoneManager = CMMotionManager()
    private let headphoneManager = CMHeadphoneMotionManager()
    private let activityManager = CMMotionActivityManager()
    
    private var recordedFrames: [RawMotionFrame] = []
    private var recordingStartTimestamp: TimeInterval?
    
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.musclecontractiontimer.capturequeue"
        q.qualityOfService = .userInteractive
        return q
    }()
    
    public override init() {
        super.init()
        iPhoneManager.deviceMotionUpdateInterval = 1.0 / 100.0
        headphoneManager.delegate = self
        requestPermissionsIfNeeded()
    }
    
    public func switchSource(to source: SensorSource) {
        guard state != .analyzing else { return }
        stopHardwareUpdates()
        selectedSource = source
        config = .preset(for: source)
    }
    
    public func startRecording() {
        recordedFrames.removeAll()
        recordedFrames.reserveCapacity(6000)
        recordingStartTimestamp = nil
        analysisResult = nil
        manualCaptureState = .idle
        manualGroundTruthReps.removeAll()
        hasSavedCurrentSet = false
        
        switch selectedSource {
        case .iPhone:
            guard iPhoneManager.isDeviceMotionAvailable else {
                state = .error("iPhone motion sensors unavailable.")
                return
            }
            AudioHandoffManager.shared.playActionCue()
            state = .recording(frameCount: 0, elapsed: 0)
            iPhoneManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
                guard let motion = motion, error == nil else { return }
                let frame = RawMotionFrame(from: motion)
                Task { @MainActor [weak self] in
                    self?.appendFrame(frame)
                }
            }
            
        case .airPods:
            AudioHandoffManager.shared.triggerAirPodsHandoff()
            guard headphoneManager.isDeviceMotionAvailable else {
                state = .error("AirPods motion unavailable.")
                return
            }
            AudioHandoffManager.shared.playActionCue()
            state = .recording(frameCount: 0, elapsed: 0)
            headphoneManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
                guard let motion = motion, error == nil else { return }
                let frame = RawMotionFrame(from: motion)
                Task { @MainActor [weak self] in
                    self?.appendFrame(frame)
                }
            }
        }
    }
    
    // MARK: - Ground Truth 4-Stage Phase Marking
    
    public func startManualPhase1() {
        guard case .recording = state, case .idle = manualCaptureState else { return }
        manualCaptureState = .inFirstPhase(startTime: currentRelativeTime())
    }
    
    public func stopManualPhase1EnterIsometric() {
        guard case .recording = state, case .inFirstPhase(let start) = manualCaptureState else { return }
        let p1End = currentRelativeTime()
        guard p1End > start + 0.05 else { return }
        manualCaptureState = .inIsometricPause(startTime: start, phase1EndTime: p1End)
    }
    
    public func transitionDirectlyToPhase2() {
        guard case .recording = state, case .inFirstPhase(let start) = manualCaptureState else { return }
        let now = currentRelativeTime()
        guard now > start + 0.05 else { return }
        manualCaptureState = .inSecondPhase(startTime: start, phase1EndTime: now, phase2StartTime: now)
    }
    
    public func startManualPhase2FromIsometric() {
        guard case .recording = state,
              case .inIsometricPause(let start, let p1End) = manualCaptureState else { return }
        let p2Start = currentRelativeTime()
        manualCaptureState = .inSecondPhase(
            startTime: start,
            phase1EndTime: p1End,
            phase2StartTime: max(p1End, p2Start)
        )
    }
    
    public func endManualPhase2() {
        guard case .recording = state,
              case .inSecondPhase(let start, let p1End, let p2Start) = manualCaptureState else { return }
        let end = currentRelativeTime()
        manualCaptureState = .idle
        
        guard end > p2Start + 0.05 else { return }
        let rep = GroundTruthRep(
            index: manualGroundTruthReps.count + 1,
            startTime: start,
            phase1EndTime: p1End,
            phase2StartTime: p2Start,
            endTime: end
        )
        manualGroundTruthReps.append(rep)
    }
    
    private func currentRelativeTime() -> TimeInterval {
        if let first = recordingStartTimestamp, let last = recordedFrames.last?.timestamp {
            return max(0.0, last - first)
        }
        return 0.0
    }
    
    public func stopRecording() {
        if case .inSecondPhase = manualCaptureState {
            endManualPhase2()
        } else {
            manualCaptureState = .idle
        }
        
        stopHardwareUpdates()
        AudioHandoffManager.shared.playActionCue()
        
        guard recordedFrames.count > 20,
              let first = recordedFrames.first?.timestamp,
              let last = recordedFrames.last?.timestamp else {
            state = .error("Recording too short (< 1 second). Please record a full set.")
            return
        }
        
        if !manualGroundTruthReps.isEmpty {
            userEnteredRepCount = manualGroundTruthReps.count
        }
        
        state = .awaitingRepCount(duration: last - first)
    }
    
    public func computeTimingsForRepCount() {
        guard !recordedFrames.isEmpty, userEnteredRepCount > 0 else { return }
        
        state = .analyzing
        let framesSnapshot = recordedFrames
        let targetReps = userEnteredRepCount
        let sourceSnapshot = selectedSource
        let orderSnapshot = phaseOrder
        let configSnapshot = config
        let groundTruthSnapshot = manualGroundTruthReps
        
        Task.detached(priority: .userInitiated) {
            let baseResult = OfflineCycleAnalyzer.analyze(
                frames: framesSnapshot,
                targetRepCount: targetReps,
                source: sourceSnapshot,
                configuration: configSnapshot,
                phaseOrder: orderSnapshot // Passes exercise sequence into the analyzer
            )
            let enrichedResult = SessionAnalysisResult(
                source: baseResult.source,
                phaseOrder: orderSnapshot,
                principalAxis: baseResult.principalAxis,
                explainedVarianceRatio: baseResult.explainedVarianceRatio,
                samples: baseResult.samples,
                cycles: baseResult.cycles,
                groundTruthReps: groundTruthSnapshot
            )
            await MainActor.run {
                self.analysisResult = enrichedResult
                self.state = .completed
            }
        }
    }
    
    /// Packages the current recording into a `PersistedMotionSet` and saves it to the provided store.
    public func saveCurrentSet(title: String, to store: MotionSetStore) {
        guard !recordedFrames.isEmpty else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "\(selectedSource.rawValue) Set (\(userEnteredRepCount) reps)" : trimmed
        
        let persisted = PersistedMotionSet(
            title: finalTitle,
            source: selectedSource,
            phaseOrder: phaseOrder,
            targetRepCount: userEnteredRepCount,
            frames: recordedFrames,
            groundTruthReps: manualGroundTruthReps
        )
        store.save(persisted)
        hasSavedCurrentSet = true
    }
    
    private func appendFrame(_ frame: RawMotionFrame) {
        if recordingStartTimestamp == nil {
            recordingStartTimestamp = frame.timestamp
        }
        recordedFrames.append(frame)
        let elapsed = frame.timestamp - (recordingStartTimestamp ?? frame.timestamp)
        state = .recording(frameCount: recordedFrames.count, elapsed: elapsed)
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
