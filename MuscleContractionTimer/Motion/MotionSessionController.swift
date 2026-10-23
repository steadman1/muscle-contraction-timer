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
        case inSecondPhase(startTime: TimeInterval, turnaroundTime: TimeInterval)
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
    
    // MARK: - Ground Truth 3-Stage Phase Marking (Phase 1 -> Turnaround -> Phase 2)
    
    public func startManualPhase1() {
        guard case .recording = state, case .idle = manualCaptureState else { return }
        manualCaptureState = .inFirstPhase(startTime: currentRelativeTime())
    }
    
    public func transitionManualToPhase2() {
        guard case .recording = state, case .inFirstPhase(let start) = manualCaptureState else { return }
        let turnaround = currentRelativeTime()
        guard turnaround > start + 0.05 else { return }
        manualCaptureState = .inSecondPhase(startTime: start, turnaroundTime: turnaround)
    }
    
    public func endManualPhase2() {
        guard case .recording = state,
              case .inSecondPhase(let start, let turnaround) = manualCaptureState else { return }
        let end = currentRelativeTime()
        manualCaptureState = .idle
        
        guard end > turnaround + 0.05 else { return }
        let rep = GroundTruthRep(
            index: manualGroundTruthReps.count + 1,
            startTime: start,
            turnaroundTime: turnaround,
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
                phaseOrder: orderSnapshot
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
