import SwiftUI

@main
struct ShowcaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        DocumentGroup(newDocument: TextDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultLaunchBehavior(.suppressed) // we seed sample docs from AppDelegate
        .defaultSize(width: 1320, height: 760) // wide enough that all 8 tabs sit full-size
    }
}

/// One document's editor. Each tab hosts one of these; the theme switcher in the
/// header drives the shared ShowcaseTheme, which re-themes the native tab bar.
struct EditorView: View {
    @Binding var document: TextDocument
    let fileURL: URL?
    @ObservedObject private var theme = ShowcaseTheme.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.on.square")
                    .foregroundStyle(theme.accent)
                Text("Right-click a tab to color it · styled natively")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.editorText)
                Spacer()
                Text("Theme")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.editorText.opacity(0.6))
                Picker("", selection: $theme.mode) {
                    ForEach(ShowcaseTheme.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.editorBackground)

            Divider()

            TextEditor(text: $document.text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(theme.editorText)
                .scrollContentBackground(.hidden)
                .background(theme.editorBackground)
                .padding(12)
        }
        .background(theme.editorBackground)
        .preferredColorScheme(theme.isLight ? .light : .dark)
        .frame(minWidth: 820, minHeight: 420)
        // Publish live text so "color from #tag" reflects unsaved edits.
        .onAppear { TabContentRegistry.shared.update(document.text, for: fileURL) }
        .onChange(of: document.text) { _, newValue in
            TabContentRegistry.shared.update(newValue, for: fileURL)
            if case .fromTag = TabColorStore.shared.choice(for: fileURL) {
                NotificationCenter.default.post(name: .tabColorsChanged, object: nil)
            }
        }
    }
}
