// RootView.swift — fixed 3-column shell (sidebar · main · inspector).
// Only the CENTER + INSPECTOR *content* swap on navigation; widths are constant.
import SwiftUI

struct BipboxRootView: View {
    @StateObject private var model = WorkspaceModel()
    @State private var appearance: ColorScheme? = nil

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 252)

            VStack(spacing: 0) {
                Toolbar(appearance: $appearance)
                Divider().overlay(BB.hair)
                HStack(spacing: 0) {
                    CenterColumn()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().overlay(BB.hair)
                    InspectorView()
                        .frame(width: 344)
                        .background(BB.panel)
                }
            }
            .background(BB.content)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .environmentObject(model)
        .preferredColorScheme(appearance)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(BB.ink, in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(BB.content)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }
}

// MARK: - Toolbar

private struct Toolbar: View {
    @EnvironmentObject var model: WorkspaceModel
    @Binding var appearance: ColorScheme?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(["sidebar.left", "chevron.left", "chevron.right"], id: \.self) { s in
                ToolbarButton(symbol: s) {}
            }
            searchField
            Spacer(minLength: 8)
            if model.section.isLibraryLike || model.isSearching { viewToggle }
            ToolbarButton(symbol: (appearance ?? scheme) == .dark ? "sun.max" : "moon") {
                appearance = (appearance ?? scheme) == .dark ? .light : .dark
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(BB.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isSearching ? "magnifyingglass" : "sparkles")
                .font(.system(size: 13)).foregroundStyle(model.isSearching ? BB.ink2 : BB.accent)
            TextField("Ask or search your files…", text: Binding(
                get: { model.query },
                set: { v in model.query = v; model.selection = v.isEmpty ? .overview : (model.search().first.map { .item($0.id) } ?? .none) }
            ))
            .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(BB.ink)
            if model.isSearching {
                Button { model.query = ""; model.selection = .overview } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BB.ink3)
                }.buttonStyle(.plain)
            } else {
                Text("⌘K").font(.system(size: 11)).foregroundStyle(BB.ink3)
            }
        }
        .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 460)
        .background(BB.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.isSearching ? BB.accent : BB.hairStrong, lineWidth: 0.5))
    }

    private var viewToggle: some View {
        HStack(spacing: 2) {
            seg(.gallery, model.isSearching ? "Results" : "Gallery", model.isSearching ? "list.bullet" : "square.grid.2x2")
            seg(.connections, model.isSearching ? "Map" : "Connections", "point.3.connected.trianglepath.dotted")
        }
        .padding(2).background(BB.chipBg, in: RoundedRectangle(cornerRadius: 8))
    }
    private func seg(_ m: LibraryMode, _ label: String, _ symbol: String) -> some View {
        Button { model.setMode(m) } label: {
            Label(label, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 11).frame(height: 26)
                .background(model.mode == m ? BB.content : .clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(model.mode == m ? BB.ink : BB.ink2)
        }.buttonStyle(.plain)
    }
}

struct ToolbarButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(hover ? BB.ink : BB.ink2)
                .frame(width: 28, height: 28)
                .background(hover ? BB.rowHover : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

// MARK: - Center column (swaps content by section / mode / search)

struct CenterColumn: View {
    @EnvironmentObject var model: WorkspaceModel
    var body: some View {
        Group {
            if model.isSearching { SearchView() }
            else {
                switch model.section {
                case .rules: RulesView()
                case .activity: ActivityView()
                case .inbox: LibraryView(forceList: true)
                default: LibraryView(forceList: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
