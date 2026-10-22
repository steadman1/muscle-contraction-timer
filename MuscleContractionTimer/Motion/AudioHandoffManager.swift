//
//  AudioHandoffManager.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import Foundation
import AVFoundation

@MainActor
public final class AudioHandoffManager {
    public static let shared = AudioHandoffManager()
    
    private var silentPlayer: AVAudioPlayer?
    private var cuePlayer: AVAudioPlayer?
    private let session = AVAudioSession.sharedInstance()
    
    private init() {
        configureSession()
        prepareBuffers()
    }
    
    private func configureSession() {
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup error: \(error.localizedDescription)")
        }
    }
    
    private func prepareBuffers() {
        let silentWAV = Self.synthesizeWAV(frequency: 0, duration: 0.25, amplitude: 0.0)
        let cueWAV = Self.synthesizeWAV(frequency: 880.0, duration: 0.12, amplitude: 0.35)
        
        silentPlayer = try? AVAudioPlayer(data: silentWAV)
        silentPlayer?.prepareToPlay()
        
        cuePlayer = try? AVAudioPlayer(data: cueWAV)
        cuePlayer?.prepareToPlay()
    }
    
    public func triggerAirPodsHandoff() {
        try? session.setActive(true)
        silentPlayer?.currentTime = 0
        silentPlayer?.play()
    }
    
    public func playActionCue() {
        if cuePlayer?.isPlaying == true { cuePlayer?.stop() }
        cuePlayer?.currentTime = 0
        cuePlayer?.play()
    }
    
    private static func synthesizeWAV(frequency: Double, duration: Double, amplitude: Double) -> Data {
        let sampleRate = 44100.0
        let numSamples = Int(sampleRate * duration)
        let dataSize = numSamples * 2
        
        var data = Data()
        data.reserveCapacity(44 + dataSize)
        
        func appendUInt32(_ val: UInt32) {
            let le = val.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: le) { Array($0) })
        }
        func appendUInt16(_ val: UInt16) {
            let le = val.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: le) { Array($0) })
        }
        
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32(UInt32(36 + dataSize))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // Mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32(UInt32(dataSize))
        
        for i in 0..<numSamples {
            let sample: Int16
            if frequency > 0 {
                let t = Double(i) / sampleRate
                let env = 1.0 - (Double(i) / Double(numSamples))
                sample = Int16(sin(2.0 * .pi * frequency * t) * amplitude * env * Double(Int16.max))
            } else {
                sample = 0
            }
            let le = sample.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: le) { Array($0) })
        }
        return data
    }
}
