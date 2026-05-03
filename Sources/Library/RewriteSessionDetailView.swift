import AppKit
import SwiftData
import SwiftUI

/// Detail surface for a single `RewriteSession` row. Three-pane layout:
/// Selection (input) → Instruction → Output. Output is the primary
/// visual block (semibold, mirrors dictation transcript treatment) since
/// it's "what the user produced". No playback / no re-transcribe / no
/// reveal-in-Finder — rewrite rows have no associated audio file.
struct RewriteSessionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: RewriteSession

    @State private var pendingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                selectionBlock
                instructionBlock
                outputBlock
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .toolbar { toolbarContent }
        .alert(
            "Delete this rewrite?",
            isPresented: $pendingDelete
        ) {
            Button("Delete", role: .destructive) {
                RecordingStore.delete(session, from: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rewrite session will be removed. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var flavorLabel: String {
        switch session.flavor {
        case "voice": return "Rewrite with Voice"
        case "fixed": return "Rewrite"
        default: return "Rewrite"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $session.title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            // Per persistence plan §5: render `flavor · modelUsed` as
            // a single grouped line — together they answer "what kind
            // + what model produced this output." Omit the line
            // entirely when `modelUsed == nil` (legacy / Apple-Intel-
            // only rows where the row's leading icon already conveys
            // kind).
            if let model = session.modelUsed, !model.isEmpty {
                Text("\(flavorLabel) · \(model)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Panes

    private var selectionBlock: some View {
        GroupBox {
            ScrollView {
                Text(session.selectionText.isEmpty ? "(no selection)" : session.selectionText)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(4)
            }
            .frame(minHeight: 80, maxHeight: 200)
        } label: {
            Text("Selected text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var instructionBlock: some View {
        GroupBox {
            ScrollView {
                Text(session.instructionText.isEmpty ? "(no instruction)" : session.instructionText)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(4)
            }
            .frame(minHeight: 60, maxHeight: 160)
        } label: {
            Text("Instruction")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var outputBlock: some View {
        GroupBox {
            ScrollView {
                Text(session.output.isEmpty ? "(empty output)" : session.output)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(4)
            }
            .frame(minHeight: 180, maxHeight: 320)
        } label: {
            Text("Rewritten output")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                copyOutput()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                pendingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func copyOutput() {
        guard let pb = AppServices.live?.pasteboard else { return }
        _ = pb.write(session.output)
    }
}
