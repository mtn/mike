import AppKit
import SwiftUI

struct MikeMenu: View {
    @Bindable var model: MikeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.menuBarIcon)
                    .font(.title2)
                    .foregroundStyle(model.isRouting ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text("Mike")
                        .font(.headline)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Label(
                    "Call feed: \(model.callFeedStatus)",
                    systemImage: model.isCallFeedMuted
                        ? "speaker.slash.fill"
                        : "speaker.wave.2.fill"
                )
                .foregroundStyle(model.isCallFeedMuted ? .orange : .secondary)

                Spacer()

                if model.isVoiceInkCapturing {
                    Text("VoiceInk active")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Picker("Microphone", selection: $model.selectedInputUID) {
                ForEach(model.inputDevices, id: \.uid) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .disabled(model.isRouting || model.followsVoiceInk)

            Toggle("Follow VoiceInk microphone", isOn: $model.followsVoiceInk)

            Text(model.voiceInkInputStatus)
                .font(.caption)
                .foregroundStyle(model.voiceInkInputWarning ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Virtual microphone", selection: $model.selectedOutputUID) {
                ForEach(model.outputDevices, id: \.uid) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .disabled(model.isRouting)

            Text("Slack: Preferences → Audio & video → Microphone → BlackHole 2ch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.isRouting {
                Text(model.metricsStatus)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(
                    model.isStarting
                        ? "Starting…"
                        : (model.isRouting ? "Stop Routing" : "Start Routing")
                ) {
                    model.toggleRouting()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isStarting)

                Button("Refresh") {
                    model.refreshDevices()
                }
                .disabled(model.isRouting)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            model.refreshDevices()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification
            )
        ) { _ in
            model.shutdown()
        }
    }
}
