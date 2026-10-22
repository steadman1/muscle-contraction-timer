//
//  AudioRoutePicker.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import AVKit
import SwiftUI

struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = .systemBlue
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
