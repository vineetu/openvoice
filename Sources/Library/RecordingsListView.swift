import AppKit
import SwiftData
import SwiftUI

/// Reusable recordings browser — date-grouped list + `searchable` toolbar +
/// detail navigation. Home uses this as its primary surface and can inject
/// optional content above the grouped recordings.
///
/// The list interleaves dictation `Recording` rows and `RewriteSession`
/// rows in chronological order (descending by `createdAt`). Each row's
/// kind is differentiated by a leading SF Symbol; both kinds push their
/// concrete model onto the navigation path and resolve to a per-kind
/// detail view via `.navigationDestination`.
struct RecordingsListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var transcriberHolder: TranscriberHolder
    /// Per-kind queries fetch the top `mergedRowCap` rows of each kind
    /// sorted by `createdAt` descending. The merge-and-cap below sorts
    /// the (≤2N) row window globally and trims to N. Top-N per kind is
    /// sufficient to compute the global top-N because each per-kind
    /// fetch is itself date-sorted descending — any row that would be
    /// in the global top-N must be in its own kind's top-N.
    @Query(Self.recordingsDescriptor)
    private var recordings: [Recording]
    @Query(Self.rewritesDescriptor)
    private var rewrites: [RewriteSession]

    private static let mergedRowCap = 50

    private static var recordingsDescriptor: FetchDescriptor<Recording> {
        var d = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        d.fetchLimit = mergedRowCap
        return d
    }

    private static var rewritesDescriptor: FetchDescriptor<RewriteSession> {
        var d = FetchDescriptor<RewriteSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        d.fetchLimit = mergedRowCap
        return d
    }

    @State private var searchText: String = ""
    @State private var path = NavigationPath()
    @State private var pendingDelete: Recording?
    @State private var pendingDeleteRewrite: RewriteSession?
    @State private var retranscribeError: String?
    private let navigationTitle: String
    private let topContent: AnyView?

    init(navigationTitle: String = "Recordings") {
        self.navigationTitle = navigationTitle
        topContent = nil
    }

    init<TopContent: View>(
        navigationTitle: String = "Recordings",
        @ViewBuilder topContent: () -> TopContent
    ) {
        self.navigationTitle = navigationTitle
        self.topContent = AnyView(topContent())
    }

    /// Result set the list renders. Empty search → the limited 50-row
    /// `@Query` results merged. Non-empty search → unlimited
    /// `context.fetch`es so older items still match. The fetches re-issue
    /// on every keystroke; bounded by the total counts (a few hundred at
    /// most), and search activates rarely enough that the cost is
    /// acceptable. Falls back to the limited sets if the unlimited fetch
    /// throws.
    private var filteredItems: [LibraryItem] {
        let recordingsPool: [Recording]
        let rewritesPool: [RewriteSession]
        if searchText.isEmpty {
            recordingsPool = recordings
            rewritesPool = rewrites
        } else {
            recordingsPool = unlimitedRecordings() ?? recordings
            rewritesPool = unlimitedRewrites() ?? rewrites
        }

        let needle = searchText.lowercased()

        let recordingItems: [LibraryItem] = recordingsPool.compactMap { r in
            if needle.isEmpty { return .recording(r) }
            if r.title.lowercased().contains(needle) || r.transcript.lowercased().contains(needle) {
                return .recording(r)
            }
            return nil
        }

        let rewriteItems: [LibraryItem] = rewritesPool.compactMap { s in
            if needle.isEmpty { return .rewrite(s) }
            if s.title.lowercased().contains(needle)
                || s.selectionText.lowercased().contains(needle)
                || s.instructionText.lowercased().contains(needle)
                || s.output.lowercased().contains(needle)
                || (s.modelUsed?.lowercased().contains(needle) ?? false) {
                return .rewrite(s)
            }
            return nil
        }

        let merged = (recordingItems + rewriteItems)
            .sorted { $0.createdAt > $1.createdAt }
        // Truncate AFTER the global sort so a fresh recording can't be
        // hidden behind a stale rewrite (or vice versa). Search results
        // bypass the cap so older matches still surface.
        if searchText.isEmpty {
            return Array(merged.prefix(Self.mergedRowCap))
        }
        return merged
    }

    private func unlimitedRecordings() -> [Recording]? {
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try? context.fetch(descriptor)
    }

    private func unlimitedRewrites() -> [RewriteSession]? {
        let descriptor = FetchDescriptor<RewriteSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try? context.fetch(descriptor)
    }

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationTitle(navigationTitle)
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search library")
                .navigationDestination(for: Recording.self) { r in
                    RecordingDetailView(recording: r)
                }
                .navigationDestination(for: RewriteSession.self) { s in
                    RewriteSessionDetailView(session: s)
                }
                .alert(
                    "Delete this recording?",
                    isPresented: Binding(
                        get: { pendingDelete != nil },
                        set: { if !$0 { pendingDelete = nil } }
                    )
                ) {
                    Button("Delete", role: .destructive) {
                        if let r = pendingDelete {
                            RecordingStore.delete(r, from: context)
                        }
                        pendingDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                } message: {
                    Text("The audio file and transcript will be removed. This cannot be undone.")
                }
                .alert(
                    "Delete this rewrite?",
                    isPresented: Binding(
                        get: { pendingDeleteRewrite != nil },
                        set: { if !$0 { pendingDeleteRewrite = nil } }
                    )
                ) {
                    Button("Delete", role: .destructive) {
                        if let s = pendingDeleteRewrite {
                            RecordingStore.delete(s, from: context)
                        }
                        pendingDeleteRewrite = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDeleteRewrite = nil }
                } message: {
                    Text("The rewrite session will be removed. This cannot be undone.")
                }
                .alert(
                    "Re-transcribe failed",
                    isPresented: Binding(
                        get: { retranscribeError != nil },
                        set: { if !$0 { retranscribeError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { retranscribeError = nil }
                } message: {
                    Text(retranscribeError ?? "")
                }
        }
    }

    private var list: some View {
        List {
            if let topContent {
                auxiliaryRow {
                    topContent
                }
            }

            if filteredItems.isEmpty {
                auxiliaryRow {
                    emptyState
                }
            } else {
                ForEach(RecordingStore.grouped(libraryItems: filteredItems), id: \.0.id) { (group, rows) in
                    Section(group.title) {
                        ForEach(rows) { item in
                            Button {
                                switch item {
                                case .recording(let r): path.append(r)
                                case .rewrite(let s): path.append(s)
                                }
                            } label: {
                                RecordingRowView(
                                    item: item,
                                    onRetranscribe: {
                                        if case .recording(let r) = item { retranscribe(r) }
                                    },
                                    onReveal: {
                                        if case .recording(let r) = item { reveal(r) }
                                    },
                                    onDelete: {
                                        switch item {
                                        case .recording(let r): pendingDelete = r
                                        case .rewrite(let s): pendingDeleteRewrite = s
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No library items yet" : "No matches")
                .font(.system(size: 13, weight: .semibold))
            Text(searchText.isEmpty
                 ? "Your dictations and rewrites will appear here."
                 : "Try a different search term.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func auxiliaryRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func retranscribe(_ r: Recording) {
        let transcriber = transcriberHolder.transcriber
        let url = RecordingStore.audioURL(for: r)
        Task {
            do {
                let result = try await transcriber.transcribeFile(url)
                await MainActor.run {
                    r.rawTranscript = result.rawText
                    r.transcript = result.text
                    try? context.save()
                }
            } catch {
                await MainActor.run {
                    retranscribeError = error.localizedDescription
                }
            }
        }
    }

    private func reveal(_ r: Recording) {
        let url = RecordingStore.audioURL(for: r)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
