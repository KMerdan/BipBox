// SidebarView.swift — grouped IA: Library · Watched Folders · Collections · Organize.
// One sidebar; selecting a row swaps center+inspector content, never a whole column.
import SwiftUI
import BipboxCore

struct SidebarView: View {
    @EnvironmentObject var model: WorkspaceModel
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with room for traffic lights.
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(hex: 0x4AA3FF), BB.accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22)
                    .overlay(Text("B").font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                Text("Bipbox").font(.system(size: 14, weight: .semibold)).foregroundStyle(BB.ink)
                Spacer()
            }
            .padding(.leading, 76).padding(.trailing, 16).frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group("") {
                        row(.allItems, "square.stack.3d.up", "All Items")
                        row(.recents, "clock", "Recents")
                        row(.inbox, "tray.and.arrow.down", "Inbox", badge: model.pendingCount)
                    }
                    group("Watched Folders", onHeaderTap: { model.go(.sources) }, onAdd: { model.addWatchedFolderViaPanel() }) {
                        manageRow()
                        ForEach(model.sources) { s in
                            row(.source(s.id), "folder", s.displayName, dot: BBPalette.color(for: s.id))
                        }
                    }
                    group("Collections") {
                        emptyHint("No collections yet")
                    }
                    group("Organize") {
                        row(.rules, "point.3.connected.trianglepath.dotted", "Rules")
                        row(.activity, "clock.arrow.circlepath", "Activity")
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            Divider().overlay(BB.hair)
            HStack(spacing: 9) {
                Circle().fill(BB.good).frame(width: 7, height: 7)
                Text("Assistant ready · local").font(.system(size: 12)).foregroundStyle(BB.ink2)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(BB.ink3)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(BB.sidebar)
    }

    @ViewBuilder
    private func group<C: View>(_ title: String, onHeaderTap: (() -> Void)? = nil, onAdd: (() -> Void)? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty {
                HStack {
                    Button { onHeaderTap?() } label: {
                        Text(title.uppercased()).font(BB.groupHead).tracking(0.4).foregroundStyle(BB.ink3)
                    }.buttonStyle(.plain).disabled(onHeaderTap == nil)
                    Spacer()
                    if let onAdd {
                        Button(action: onAdd) {
                            Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(BB.ink3)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 6)
            } else {
                Spacer().frame(height: 6)
            }
            content()
        }
    }

    /// Always-present entry into the source manager (the north star's "Start").
    @ViewBuilder
    private func manageRow() -> some View {
        if model.sources.isEmpty {
            Button { model.go(.sources) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 14)).frame(width: 17)
                        .foregroundStyle(model.section == .sources ? BB.accent : BB.accent)
                    Text("Add a folder…").font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(model.section == .sources ? BB.accent : BB.accent)
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(model.section == .sources ? BB.selFill : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        } else {
            row(.sources, "slider.horizontal.3", "Manage Sources")
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(BB.ink3)
            .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func row(_ s: WorkspaceNav, _ symbol: String, _ title: String, badge: Int? = nil, dot: Color? = nil) -> some View {
        let selected = model.section == s
        return Button { model.go(s) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 17)
                    .foregroundStyle(selected ? BB.accent : BB.ink2)
                Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? BB.accent : BB.ink).lineLimit(1)
                Spacer(minLength: 4)
                if let badge, badge > 0 {
                    Text("\(badge)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minWidth: 19, minHeight: 19)
                        .background(BB.accent, in: Capsule())
                }
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(selected ? BB.selFill : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.\(WorkspaceModel.navString(s))")
    }
}
