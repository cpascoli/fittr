import AVKit
import SwiftUI
import UIKit

struct TechniqueView: View {
    let exercise: ExerciseDefinition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TechniqueClipView(exercise: exercise)
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
}

struct TechniqueClipView: View {
    let exercise: ExerciseDefinition
    var height: CGFloat = 220
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var frameImages: [UIImage] = []
    @State private var frameIndex = 0

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if !frameImages.isEmpty {
                Color.clear
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        Image(uiImage: frameImages[frameIndex % frameImages.count])
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FittrTheme.cardElevated)
                        .frame(height: height)
                    VStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.largeTitle)
                        Text(exercise.name)
                            .font(.headline)
                        Text("Technique clip unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("workout.techniqueClip")
        .onAppear { configureMedia() }
        .onDisappear { player?.pause() }
        .onReceive(Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()) { _ in
            guard frameImages.count > 1, player == nil else { return }
            frameIndex = (frameIndex + 1) % frameImages.count
        }
    }

    private func configureMedia() {
        if let url = TechniqueMedia.videoURL(for: exercise) {
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: item)
            queue.play()
            player = queue
            return
        }
        frameImages = TechniqueMedia.frameImages(for: exercise)
        frameIndex = 0
    }
}

enum TechniqueMedia {
    static func videoURL(for exercise: ExerciseDefinition) -> URL? {
        let name = resourceName(for: exercise)
        if let bundled = bundledResource(name, extension: "mp4") {
            return bundled
        }
        if !exercise.remoteVideoURL.isEmpty, let remote = URL(string: exercise.remoteVideoURL) {
            return remote
        }
        return nil
    }

    static func url(for exercise: ExerciseDefinition) -> URL? {
        videoURL(for: exercise)
    }

    static func frameImages(for exercise: ExerciseDefinition) -> [UIImage] {
        let name = resourceName(for: exercise)
        return (1...4).compactMap { index in
            let resource = "\(name)-\(index)"
            if let named = UIImage(named: resource) {
                return named
            }
            return bundledResource(resource, extension: "jpg")
                .flatMap { UIImage(contentsOfFile: $0.path) }
        }
    }

    private static func resourceName(for exercise: ExerciseDefinition) -> String {
        exercise.localVideoName.isEmpty ? exercise.slug : exercise.localVideoName
    }

    private static func bundledResource(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Media/Technique")
    }
}
