//
//  ContractionPhaseTimingProgressionView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/26/26.
//

import SwiftUI

fileprivate let cardSize: CGSize = .init(width: 188, height: 144)

public struct ContractionPhaseTimingProgressionView: View {
    @ObservedObject private var timingStore = ExerciseTimingStore.shared
    
    public let exerciseName: String
    public let phase: ContractionPhase
    private let customDuration: Double?
    private let customUnit: String?
    private let customSubtitle: String?
    private let customDataPoints: [Double]?
    public var onTap: () -> Void = {}
    
    /// Initializes the card connected to the persistent `ExerciseTimingStore` for an exercise and contraction phase.
    public init(
        exerciseName: String,
        phase: ContractionPhase = .eccentric,
        onTap: @escaping () -> Void = {}
    ) {
        self.exerciseName = exerciseName
        self.phase = phase
        self.customDuration = nil
        self.customUnit = nil
        self.customSubtitle = nil
        self.customDataPoints = nil
        self.onTap = onTap
    }
    
    /// Initializes the card with custom timing metrics and data points.
    public init(
        title: String,
        timingDuration: Double?,
        unit: String = "s",
        subtitle: String,
        dataPoints: [Double],
        phase: ContractionPhase = .eccentric,
        onTap: @escaping () -> Void = {}
    ) {
        self.exerciseName = title
        self.phase = phase
        self.customDuration = timingDuration
        self.customUnit = unit
        self.customSubtitle = subtitle
        self.customDataPoints = dataPoints
        self.onTap = onTap
    }
    
    // MARK: - Computed Timing Metrics from Persistence
    
    private var chronologicalRecords: [ExerciseTimingRecord] {
        timingStore.records(for: exerciseName).sorted { $0.date < $1.date }
    }
    
    private var dataPoints: [Double] {
        if let custom = customDataPoints {
            return custom
        }
        let storedPoints = chronologicalRecords.compactMap { record in
            let duration = phase == .eccentric ? record.eccentricDuration : record.concentricDuration
            return duration > 0 ? duration : nil
        }
        return storedPoints
    }
    
    private var displayDuration: Double? {
        if let custom = customDuration {
            return custom
        }
        return phase == .eccentric
            ? timingStore.averageEccentric(for: exerciseName)
            : timingStore.averageConcentric(for: exerciseName)
    }
    
    private var unit: String {
        customUnit ?? "s"
    }
    
    private var subtitle: String {
        if let custom = customSubtitle {
            return custom
        }
        return "Avg \(phase.rawValue)"
    }
    
    private var formattedDurationText: String {
        guard let duration = displayDuration, duration > 0 else {
            return "—"
        }
        return String(format: "%.2f", duration)
    }
    
    // MARK: - Color Styling
    
    private var lineGradient: LinearGradient {
        if phase == .eccentric {
            return LinearGradient(
                colors: [
                    Color.orange,
                    Color(red: 1.0, green: 0.36, blue: 0.55)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.45, green: 0.35, blue: 0.95),
                    Color(red: 0.75, green: 0.45, blue: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    private var endCapColor: Color {
        phase == .eccentric
            ? Color(red: 1.0, green: 0.36, blue: 0.55)
            : Color(red: 0.75, green: 0.45, blue: 1.0)
    }
    
    // MARK: - View Body
    
    public var body: some View {
        ZStack(alignment: .topLeading) {
            // MARK: - Graph Layer (Flush to leading edge)
            GeometryReader { geo in
                let graphTopInset: CGFloat = 82
                let graphBottomInset: CGFloat = 18
                let endInset: CGFloat = Constants.Padding.m + 6
                
                let plotWidth = geo.size.width - endInset
                let plotHeight = geo.size.height - graphTopInset - graphBottomInset
                
                let points = normalizedPoints(
                    in: CGSize(width: plotWidth, height: plotHeight),
                    topOffset: graphTopInset
                )
                
                if points.count > 1, let lastPoint = points.last {
                    // Area fill under curve
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for point in points {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: lastPoint.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                endCapColor.opacity(0.18),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Main Gradient Line
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        lineGradient,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Glowing End Point Indicator
                    ZStack {
                        Circle()
                            .fill(endCapColor.opacity(0.25))
                            .frame(width: 24, height: 24)
                            .blur(radius: 3)
                        
                        Circle()
                            .fill(Color.foreground)
                            .frame(width: 14, height: 14)
                        
                        Circle()
                            .fill(endCapColor)
                            .frame(width: 9, height: 9)
                    }
                    .position(lastPoint)
                } else if points.count == 1, let singlePoint = points.first {
                    // Single point indicator with reference line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: singlePoint.y))
                        path.addLine(to: singlePoint)
                    }
                    .stroke(
                        lineGradient,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])
                    )
                    
                    Circle()
                        .fill(endCapColor)
                        .frame(width: 8, height: 8)
                        .position(singlePoint)
                }
            }
            
            // MARK: - Text & Header Layer
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(exerciseName)
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.tertiaryText)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formattedDurationText)
                        .font(Fonts.headline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    
                    if displayDuration != nil {
                        Text(unit)
                            .font(Fonts.subheadline)
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
                
                Text(subtitle)
                    .font(Fonts.subheadline)
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(Constants.Padding.m)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(Color.foreground)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.l))
        .compositingGroup()
        .shadow(color: Color.shadow, radius: 4, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    // MARK: - Helpers
    
    private func normalizedPoints(in size: CGSize, topOffset: CGFloat) -> [CGPoint] {
        guard !dataPoints.isEmpty else { return [] }
        if dataPoints.count == 1 {
            return [CGPoint(x: size.width, y: topOffset + size.height * 0.5)]
        }
        
        let minVal = dataPoints.min() ?? 0
        let maxVal = dataPoints.max() ?? 1
        let range = max(maxVal - minVal, 0.01)
        
        return dataPoints.enumerated().map { index, value in
            let x = size.width * (CGFloat(index) / CGFloat(dataPoints.count - 1))
            let normalizedY = CGFloat((value - minVal) / range)
            let y = topOffset + size.height * (1.0 - normalizedY)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Backward Compatibility Alias

public typealias VolumeGraphCardView = ContractionPhaseTimingProgressionView

#Preview {
    VStack(spacing: 20) {
        ContractionPhaseTimingProgressionView(
            title: "Back Squat",
            timingDuration: 3.42,
            unit: "s",
            subtitle: "Avg Eccentric",
            dataPoints: [2.8, 3.0, 3.2, 3.1, 3.4, 3.5, 3.42],
            phase: .eccentric
        )
        
        ContractionPhaseTimingProgressionView(
            title: "Pull Ups",
            timingDuration: 1.15,
            unit: "s",
            subtitle: "Avg Concentric",
            dataPoints: [0.9, 1.0, 1.2, 1.1, 1.3, 1.15],
            phase: .concentric
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.background)
}
