import AppKit
import MumbleDictionary
import SwiftUI

/// An editable local lexicon that teaches recognition and final text the user's language.
struct DictionaryPanel: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                    Text("Dictionary")
                        .font(AppStyle.Font.display)
                        .foregroundStyle(AppStyle.Color.ink)
                    Text("Teach Mumble the names and phrases that matter to you.")
                        .font(AppStyle.Font.body)
                        .foregroundStyle(AppStyle.Color.muted)
                }
                Spacer()
                Button { isAdding = true } label: {
                    Label("Add entry", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Color.teal)
            }

            AppSurface(padding: 0) {
                VStack(spacing: 0) {
                    SearchField(text: $query, placeholder: "Search your vocabulary")
                    if entries.isEmpty {
                        EmptyPanel(
                            label: store.entries.isEmpty ? "No vocabulary yet" : "No matching entries",
                            detail: store.entries.isEmpty
                                ? "Add a term or a rule for a phrase Mumble often misses."
                                : "Try another search."
                        )
                        .frame(minHeight: 280)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: AppStyle.Metric.small) {
                                ForEach(entries) { entry in
                                    DictionaryEntryRow(
                                        entry: entry,
                                        onEdit: { editing = entry },
                                        onToggle: {
                                            var changed = entry
                                            changed.isEnabled.toggle()
                                            store.update(changed)
                                        },
                                        onDelete: { store.delete(entry) }
                                    )
                                }
                            }
                            .padding(AppStyle.Metric.standard)
                        }
                        .frame(minHeight: 280)
                    }
                    HStack {
                        Text("\(store.entries.count) saved entr\(store.entries.count == 1 ? "y" : "ies")")
                        Spacer()
                        Button("Reveal file") {
                            NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                        }
                    }
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(AppStyle.Color.muted)
                    .padding(AppStyle.Metric.standard)
                    .background(AppStyle.Color.surfaceMuted)
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }
}

private struct DictionaryEntryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.Metric.standard) {
            Image(systemName: entry.kind == .correction ? "arrow.left.arrow.right" : "textformat")
                .foregroundStyle(entry.kind == .correction ? AppStyle.Color.gold : AppStyle.Color.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                if entry.kind == .correction {
                    Text(entry.hear)
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.muted)
                    Text(entry.write)
                        .font(AppStyle.Font.bodyStrong)
                        .foregroundStyle(AppStyle.Color.ink)
                } else {
                    Text(entry.write)
                        .font(AppStyle.Font.bodyStrong)
                        .foregroundStyle(AppStyle.Color.ink)
                    Text("Recognition term")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.muted)
                }
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { entry.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(AppStyle.Color.muted)
                .help("Delete entry")
        }
        .opacity(entry.isEnabled ? 1 : 0.5)
        .padding(AppStyle.Metric.standard)
        .background(AppStyle.Color.surfaceMuted, in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
    }
}

private struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var isValid: Bool { !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty) }
    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
            HStack {
                VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                    Text(entry == nil ? "New entry" : "Edit entry")
                        .font(AppStyle.Font.title)
                        .foregroundStyle(AppStyle.Color.ink)
                    Text("Changes apply to the next recording.")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.muted)
                }
                Spacer()
                Button(action: { dismiss() }) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppStyle.Color.muted)
            }

            Picker("Entry type", selection: $kind) {
                Text("Recognition term").tag(DictionaryEntry.Kind.term)
                Text("Correction rule").tag(DictionaryEntry.Kind.correction)
            }
            .pickerStyle(.segmented)

            if kind == .correction {
                editorField("When Mumble hears", placeholder: "for example, voice memo", text: $hear)
            }
            editorField(
                kind == .correction ? "Write instead" : "Term",
                placeholder: kind == .correction ? "for example, Voice Memo" : "for example, Morning Pages",
                text: $write
            )

            ForEach(warnings) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(AppStyle.Color.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppStyle.Color.teal)
                .disabled(!isValid)
            }
        }
        .padding(AppStyle.Metric.section)
        .frame(width: 500)
        .background(AppWindowBackground())
    }

    private func editorField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
            AppLabel(text: label)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(AppStyle.Font.body)
                .padding(AppStyle.Metric.standard)
                .background(AppStyle.Color.surface, in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
                .overlay { RoundedRectangle(cornerRadius: AppStyle.Metric.smallRadius).strokeBorder(AppStyle.Color.line) }
        }
    }
}
