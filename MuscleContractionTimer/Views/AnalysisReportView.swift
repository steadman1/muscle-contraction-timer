//
//  AnalysisReportView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import SwiftUI
import Charts

public struct AnalysisReportView: View {
    public let result: SessionAnalysisResult
    
    public init(result: SessionAnalysisResult) {
        self.result = result
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            summaryMetricsGrid
            if !result.accuracyComparisons.isEmpty {
                accuracySummaryCard
            }
            displacementChartCard
            cycleTimingsList
        }
    }
    
    private var summaryMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            metricTile(title: "Avg Ecc", value: String(format: "%.2fs", result.averageEccentricDuration), unit: "lengthen")
            metricTile(title: "Avg Iso", value: String(format: "%.2fs", result.averageIsometricDuration), unit: "hold/pause")
            metricTile(title: "Avg Con", value: String(format: "%.2fs", result.averageConcentricDuration), unit: "shorten")
            metricTile(title: "Avg ROM", value: String(format: "%.1f", result.averageROMCentimeters), unit: "cm")
        }
    }
    
    private var accuracySummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Algorithm vs. Manual Ground Truth")
                    .font(.headline)
                Spacer()
                Text("\(result.accuracyComparisons.count) paired reps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricTile(
                    title: "Ecc MAE",
                    value: String(format: "%.2fs", result.meanAbsoluteEccentricError ?? 0),
                    unit: "ecc error"
                )
                metricTile(
                    title: "Iso MAE",
                    value: String(format: "%.2fs", result.meanAbsoluteIsometricError ?? 0),
                    unit: "pause error"
                )
                metricTile(
                    title: "Con MAE",
                    value: String(format: "%.2fs", result.meanAbsoluteConcentricError ?? 0),
                    unit: "con error"
                )
                metricTile(
                    title: "Overlap",
                    value: String(format: "%.0f%%", (result.meanIoU ?? 0) * 100),
                    unit: "IoU match"
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func metricTile(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline.bold().monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(10)
    }
    
    private var displacementChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segmented Displacement & Isometric Windows")
                    .font(.headline)
                Spacer()
                Text(String(format: "PCA Linearity: %.0f%%", result.explainedVarianceRatio * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Chart {
                ForEach(result.cycles) { cycle in
                    RectangleMark(
                        xStart: .value("Start", cycle.startTime),
                        xEnd: .value("End", cycle.endTime)
                    )
                    .foregroundStyle(.green.opacity(0.13))
                    
                    RectangleMark(
                        xStart: .value("Iso Start", cycle.phase1EndTime),
                        xEnd: .value("Iso End", cycle.phase2StartTime)
                    )
                    .foregroundStyle(.orange.opacity(0.32))
                }
                
                ForEach(result.groundTruthReps) { gt in
                    RuleMark(x: .value("GT Start", gt.startTime))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(.purple)
                    RuleMark(x: .value("GT End", gt.endTime))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(.purple)
                }
                
                ForEach(result.samples) { sample in
                    LineMark(
                        x: .value("Time (s)", sample.time),
                        y: .value("Displacement (cm)", sample.displacement * 100.0)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 230)
            .chartXAxisLabel("Time (seconds)")
            .chartYAxisLabel("cm")
            
            HStack(spacing: 12) {
                Label("Active Rep", systemImage: "square.fill")
                    .foregroundColor(.green)
                Label("Isometric Hold", systemImage: "square.fill")
                    .foregroundColor(.orange)
                if !result.groundTruthReps.isEmpty {
                    Label("Manual Start/End", systemImage: "line.vertical.and.line.vertical")
                        .foregroundColor(.purple)
                }
            }
            .font(.caption2)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var cycleTimingsList: some View {
        let comparisons = Dictionary(uniqueKeysWithValues: result.accuracyComparisons.map { ($0.index, $0) })
        let p1Label = result.phaseOrder.firstPhase.rawValue
        let p2Label = result.phaseOrder.secondPhase.rawValue
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Per-Repetition Phase Timings")
                    .font(.headline)
                Spacer()
                Text(result.phaseOrder.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(result.cycles) { cycle in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Rep #\(cycle.index)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(String(format: "Algo Total: %.2f s", cycle.totalDuration))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundColor(.blue)
                    }
                    
                    HStack(spacing: 10) {
                        Text(String(format: "%@: %.2fs", p1Label, cycle.phase1Duration))
                        Text("•")
                        Text(String(format: "Iso: %.2fs", cycle.isometricDuration))
                            .foregroundColor(.orange)
                        Text("•")
                        Text(String(format: "%@: %.2fs", p2Label, cycle.phase2Duration))
                        Spacer()
                        Text(String(format: "%.1f cm", cycle.romMeters * 100.0))
                            .foregroundColor(.secondary)
                    }
                    .font(.caption.bold().monospacedDigit())
                    
                    Text(String(format: "Window: %.2fs → [Iso: %.2fs–%.2fs] → %.2fs", cycle.startTime, cycle.phase1EndTime, cycle.phase2StartTime, cycle.endTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    
                    if let comp = comparisons[cycle.index] {
                        Divider()
                        HStack {
                            Text(String(format: "Manual: %.2fs (%@: %.2fs | Iso: %.2fs | %@: %.2fs)", comp.groundTruth.totalDuration, p1Label, comp.groundTruth.phase1Duration, comp.groundTruth.isometricDuration, p2Label, comp.groundTruth.phase2Duration))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.purple)
                            Spacer()
                            Text(String(format: "IoU: %.0f%%", comp.intersectionOverUnion * 100))
                                .font(.caption.bold().monospacedDigit())
                        }
                        
                        HStack(spacing: 10) {
                            Text(String(format: "ΔEcc: %+.2fs", comp.eccentricDurationError))
                            Text(String(format: "ΔIso: %+.2fs", comp.isometricDurationError))
                            Text(String(format: "ΔCon: %+.2fs", comp.concentricDurationError))
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color(uiColor: .tertiarySystemBackground))
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}
