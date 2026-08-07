import SwiftUI

struct WaveformOverlayView: View {
    @ObservedObject var appState: AppState

    @State private var currentVolume: Float = 0.0

    private let minH: CGFloat = 6
    private let maxH: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            // Cancel Button
            Button(action: {
                appState.hotkeyManager?.cancelRecording()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 4)
            
            HStack(spacing: 5) {
                bar(index: 0)
                bar(index: 1)
                bar(index: 2)
                bar(index: 3)
            }
            if !appState.liveTranscript.isEmpty {
                Text(appState.liveTranscript)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 360, alignment: .leading)
            }
            
            // Confirm Button
            Button(action: {
                appState.hotkeyManager?.stopRecordingAndTranscribe()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color(hex: 0x202020).opacity(0.92)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        .onReceive(appState.audioEngine.volumePublisher) { volume in
            withAnimation(.linear(duration: 0.05)) {
                self.currentVolume = volume
            }
        }
    }

    @ViewBuilder
    private func bar(index: Int) -> some View {
        let normalized = min(1.0, currentVolume * 10.0)
        let targetHeight = normalized < 0.05 ? minH : minH + CGFloat(normalized) * (maxH - minH)
        
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 4, height: targetHeight)
    }
}
