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
        HStack(spacing: 0) {
            GroupSidebar()
                .frame(width: 200)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(theme.accent)
                    Text("Groups in the sidebar · right-click a tab to color it")
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
        }
        .background(theme.editorBackground)
        .preferredColorScheme(theme.isLight ? .light : .dark)
        .frame(minWidth: 900, minHeight: 420)
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

/// Left sidebar listing groups (colored dot + name + count). Click a group header
/// to collapse/expand its tabs in the single tab bar; click a file to select it.
struct GroupSidebar: View {
    @ObservedObject private var manager = TabGroupManager.shared
    @ObservedObject private var theme = ShowcaseTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("GROUPS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.editorText.opacity(0.45))
                Spacer()
                Button {
                    if let name = TabContextMenuController.promptName(
                        title: "New Group", default: "Group \(manager.groups.count + 1)") {
                        manager.addGroup(name: name)
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.editorText.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("New group (then right-click a tab → Move to Group)")
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(manager.groups) { group in
                        Button { manager.toggle(group.id) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: group.expanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.editorText.opacity(0.5))
                                Circle().fill(Color(nsColor: group.color)).frame(width: 9, height: 9)
                                Text(group.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.editorText)
                                Spacer()
                                Text("\(manager.count(group.name))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.editorText.opacity(0.4))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if group.expanded {
                            ForEach(manager.urls(in: group.name), id: \.self) { url in
                                Button { manager.select(url) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color(nsColor: group.color))
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 11))
                                            .foregroundStyle(theme.editorText.opacity(0.8))
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.leading, 30).padding(.trailing, 12).padding(.vertical, 3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.editorBackground)
    }
}
