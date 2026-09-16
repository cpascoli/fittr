import SwiftUI

/// Shown instead of the app when the SwiftData store will not open.
///
/// The priority order is deliberate: get the raw files off the device first, retry
/// second, destroy last. When the store cannot be opened, a JSON export is impossible
/// — the only way to preserve the training history is to share the store files
/// themselves, so that option comes before the reset button.
struct StoreRecoveryView: View {
    let failure: StoreFailure
    var onRetry: () -> Void

    @State private var confirmingReset = false
    @State private var resetError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(FittrTheme.warning)

                Text("Fittr can't open your workout data")
                    .font(.largeTitle.weight(.bold))

                Text("This usually means the data format changed in a new build. Your workouts are still on this iPhone — save a copy before resetting anything.")
                    .foregroundStyle(.secondary)

                if !failure.files.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1 · SAVE A COPY")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("Export the raw data files to Files or AirDrop. They can be restored into a future build.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ShareLink(items: failure.files) {
                            Label("Export data files", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GymButtonStyle())
                    }
                    .fittrCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("2 · TRY AGAIN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Worth one attempt — a failed open is sometimes transient.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again", action: onRetry)
                        .buttonStyle(SecondaryGymButtonStyle())
                }
                .fittrCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("3 · START OVER")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FittrTheme.danger)
                    Text("Deletes every workout, record and setting on this iPhone, permanently. Only do this after exporting above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Delete data and start fresh") {
                        confirmingReset = true
                    }
                    .buttonStyle(SecondaryGymButtonStyle())
                    .foregroundStyle(FittrTheme.danger)
                }
                .fittrCard()

                if let resetError {
                    Text(resetError)
                        .font(.caption)
                        .foregroundStyle(FittrTheme.danger)
                }

                DisclosureGroup("Technical detail") {
                    Text(failure.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .tint(.secondary)
            }
            .padding(20)
        }
        .background(FittrTheme.background)
        .confirmationDialog(
            "Delete all Fittr data?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive, action: reset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every logged workout, personal record and setting is removed from this iPhone. This cannot be undone.")
        }
    }

    private func reset() {
        do {
            try FittrSchema.deleteStoreFiles()
            resetError = nil
            onRetry()
        } catch {
            resetError = "Could not delete the data files: \(error.localizedDescription)"
        }
    }
}
