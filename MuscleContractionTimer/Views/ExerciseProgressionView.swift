//
//  ExerciseProgressionView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/26/26.
//

import SwiftUI

struct ExerciseProgressionView: View {
    let exerciseName: String
    
    @ObservedObject private var timingStore = ExerciseTimingStore.shared
    @Environment(\.dismiss) private var dismiss
    
    private var records: [ExerciseTimingRecord] {
        timingStore.records(for: exerciseName)
    }
    
    private var workoutGroups: [WorkoutTimingGroup] {
        timingStore.workoutGroups(for: exerciseName)
    }
    
    private var avgEccentric: TimeInterval? {
        timingStore.averageEccentric(for: exerciseName)
    }
    
    private var avgConcentric: TimeInterval? {
        timingStore.averageConcentric(for: exerciseName)
    }
    
    private var tempoRatioString: String {
        guard let ecc = avgEccentric, let con = avgConcentric, con > 0 else {
            return "—"
        }
        return String(format: "%.1f : 1", ecc / con)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.Padding.m) {
                    if records.isEmpty {
                        emptyStateView
                    } else {
                        summaryStatsGrid
                        
                        VStack(alignment: .leading, spacing: Constants.Padding.s) {
                            Text("Workout History")
                                .font(Fonts.headline)
                                .foregroundStyle(Color.primaryText)
                                .padding(.horizontal, Constants.Padding.s)
                            
                            ForEach(workoutGroups) { group in
                                workoutGroupCard(group: group)
                            }
                        }
                    }
                }
                .padding(Constants.Padding.m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.background)
            .navigationTitle("\(exerciseName) Timings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Fonts.headline)
                    .foregroundStyle(Color.orange)
                }
            }
        }
    }
    
    // MARK: - Summary Stats Grid
    
    private var summaryStatsGrid: some View {
        VStack(spacing: Constants.Padding.s) {
            HStack(spacing: Constants.Padding.s) {
                kpiCard(
                    title: "Avg Eccentric",
                    value: avgEccentric.map { String(format: "%.2fs", $0) } ?? "—",
                    subtitle: "Lowering Phase",
                    systemImage: "arrow.down.right",
                    tint: .orange
                )
                
                kpiCard(
                    title: "Avg Concentric",
                    value: avgConcentric.map { String(format: "%.2fs", $0) } ?? "—",
                    subtitle: "Lifting Phase",
                    systemImage: "arrow.up.right",
                    tint: .purple
                )
            }
            
            HStack(spacing: Constants.Padding.s) {
                kpiCard(
                    title: "Tempo Ratio",
                    value: tempoRatioString,
                    subtitle: "Eccentric : Concentric",
                    systemImage: "speedometer",
                    tint: .blue
                )
                
                kpiCard(
                    title: "Tracked Sets",
                    value: "\(records.count)",
                    subtitle: "\(workoutGroups.count) Workouts",
                    systemImage: "chart.bar.fill",
                    tint: .green
                )
            }
        }
    }
    
    private func kpiCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(Fonts.subheadline)
                Text(title)
                    .font(Fonts.subheadline)
                    .foregroundStyle(Color.secondaryText)
                Spacer()
            }
            
            Text(value)
                .font(Fonts.title)
                .monospacedDigit()
                .foregroundStyle(Color.primaryText)
                .padding(.top, 2)
            
            Text(subtitle)
                .font(Fonts.subhead)
                .foregroundStyle(Color.tertiaryText)
        }
        .padding(Constants.Padding.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.foreground)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
        .compositingGroup()
        .shadow(color: Color.shadow, radius: 4, y: 2)
    }
    
    // MARK: - Workout Group Card
    
    private func workoutGroupCard(group: WorkoutTimingGroup) -> some View {
        VStack(alignment: .leading, spacing: Constants.Padding.s) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.workoutName)
                        .font(Fonts.headline)
                        .foregroundStyle(Color.primaryText)
                    
                    Text(group.dateFormatted)
                        .font(Fonts.subhead)
                        .foregroundStyle(Color.secondaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "Avg %.2fs ecc • %.2fs con", group.averageEccentric, group.averageConcentric))
                        .font(Fonts.subhead)
                        .foregroundStyle(Color.primaryText)
                        .monospacedDigit()
                    
                    if group.maxWeight > 0 {
                        Text(String(format: "Top: %.0f lbs", group.maxWeight))
                            .font(Fonts.subhead)
                            .foregroundStyle(Color.secondaryText)
                    }
                }
            }
            .padding(.bottom, 4)
            
            Divider()
            
            VStack(spacing: Constants.Padding.xs) {
                ForEach(group.records) { record in
                    setRow(record: record)
                }
            }
        }
        .padding(Constants.Padding.m)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.foreground)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
        .compositingGroup()
        .shadow(color: Color.shadow, radius: 4, y: 2)
    }
    
    private func setRow(record: ExerciseTimingRecord) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: Constants.Padding.s) {
                Text("\(record.setNumber)")
                    .font(Fonts.headline)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color.primaryText)
                    .background(
                        Circle()
                            .fill(Color.background)
                            .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
                    )
                
                Text(String(format: "%.0f lbs × %d", record.weight, record.reps))
                    .font(Fonts.body)
                    .foregroundStyle(Color.primaryText)
                
                Spacer()
                
                // Timing Pills
                HStack(spacing: 6) {
                    timingPill(
                        label: "ecc",
                        duration: record.eccentricDuration,
                        color: .orange
                    )
                    
                    timingPill(
                        label: "con",
                        duration: record.concentricDuration,
                        color: .purple
                    )
                }
            }
            
            // Visual dual-bar ratio representation
            if record.totalDuration > 0 {
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let eccRatio = CGFloat(record.eccentricDuration / record.totalDuration)
                    let conRatio = CGFloat(record.concentricDuration / record.totalDuration)
                    
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: max(4, totalWidth * eccRatio))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple.opacity(0.85))
                            .frame(width: max(4, totalWidth * conRatio))
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func timingPill(label: String, duration: TimeInterval, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(String(format: "%.2fs", duration))
                .font(Fonts.subheadline)
                .monospacedDigit()
                .foregroundStyle(color)
            
            Text(label)
                .font(Fonts.subhead)
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.s)
                .fill(color.opacity(0.12))
                .strokeBorder(color.opacity(0.25), lineWidth: Constants.strokeWidth)
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: Constants.Padding.m) {
            Spacer().frame(height: 40)
            
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56))
                .foregroundStyle(Color.orange.opacity(0.8))
                .padding(.bottom, Constants.Padding.s)
            
            Text("No Timings Recorded Yet")
                .font(Fonts.title)
                .foregroundStyle(Color.primaryText)
            
            Text("When you record and complete sets for \(exerciseName) during active workouts, your eccentric and concentric contraction timings will automatically persist and appear here across all workouts.")
                .font(Fonts.body)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Constants.Padding.l)
            
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(Constants.Padding.l)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.foreground)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
    }
}

#Preview {
    ExerciseProgressionView(exerciseName: "Back Squat")
}
