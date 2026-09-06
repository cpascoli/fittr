import AVKit
import SwiftUI

struct TechniqueView: View {
    let exercise: ExerciseDefinition
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    video
                    Text(exercise.name)
                        .font(.largeTitle.weight(.bold))
                    section("Setup", exercise.setupInstructions)
                    section("Movement", exercise.movementInstructions)
                    section("Breathing", exercise.breathingCue)
                    labeledList("Technique cues", exercise.coachingCues)
                    labeledList("Common mistakes", exercise.commonMistakes)
                    Text("Guidance is conventional coaching, not medical advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(FittrTheme.background)
            .navigationTitle("Technique")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { configurePlayer() }
            .onDisappear {
                player?.pause()
            }
        }
    }

    @ViewBuilder
    private var video: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FittrTheme.cardElevated)
                    .frame(height: 220)
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.largeTitle)
                    Text("Add \(exercise.slug).mp4 in Media/Technique to replace this placeholder.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body)
        }
    }

    private func labeledList(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
            }
        }
    }

    private func configurePlayer() {
        guard let url = TechniqueMedia.url(for: exercise) else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        queue.play()
        player = queue
    }
}

enum TechniqueMedia {
    static func url(for exercise: ExerciseDefinition) -> URL? {
        let name = exercise.localVideoName.isEmpty ? exercise.slug : exercise.localVideoName
        if let bundled = Bundle.main.url(forResource: name, withExtension: "mp4") {
            return bundled
        }
        if !exercise.remoteVideoURL.isEmpty, let remote = URL(string: exercise.remoteVideoURL) {
            return remote
        }
        return nil
    }
}
