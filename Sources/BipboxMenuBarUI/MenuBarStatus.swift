import AppKit
import BipboxCore
import Foundation

public enum MenuBarStatus: Equatable, Sendable {
    case running
    case paused
    case needsReview(Int)
    case error(String)

    public var title: String {
        switch self {
        case .running:
            "Bipbox Running"
        case .paused:
            "Bipbox Paused"
        case .needsReview(let count):
            count == 1 ? "1 Item in Inbox" : "\(count) Items in Inbox"
        case .error(let message):
            "Bipbox Error: \(message)"
        }
    }

    public var systemImageName: String {
        switch self {
        case .running:
            "tray.and.arrow.down"
        case .paused:
            "pause.circle"
        case .needsReview:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        }
    }
}

@MainActor
public protocol MenuBarCommandHandling: AnyObject {
    func openWorkspace()
    func pauseOrganizer()
    func resumeOrganizer()
    func showRecentActivity()
    func focusQuickSearch()
    func submitDroppedFileURLs(_ urls: [URL])
    func quit()
}

@MainActor
public final class MenuBarStatusViewModel {
    public private(set) var status: MenuBarStatus
    public weak var commandHandler: MenuBarCommandHandling?
    public var onChange: ((MenuBarStatus) -> Void)?

    public init(status: MenuBarStatus = .running, commandHandler: MenuBarCommandHandling? = nil) {
        self.status = status
        self.commandHandler = commandHandler
    }

    public var statusTitle: String {
        status.title
    }

    public var systemImageName: String {
        status.systemImageName
    }

    public var pauseResumeTitle: String {
        status == .paused ? "Resume Organizing" : "Pause Organizing"
    }

    public func update(status: MenuBarStatus) {
        guard self.status != status else {
            return
        }
        self.status = status
        onChange?(status)
    }

    public func openWorkspace() {
        commandHandler?.openWorkspace()
    }

    public func togglePauseResume() {
        if status == .paused {
            commandHandler?.resumeOrganizer()
        } else {
            commandHandler?.pauseOrganizer()
        }
    }

    public func showRecentActivity() {
        commandHandler?.showRecentActivity()
    }

    public func focusQuickSearch() {
        commandHandler?.focusQuickSearch()
    }

    public func submitDroppedFileURLs(_ urls: [URL]) {
        commandHandler?.submitDroppedFileURLs(urls)
    }

    public func quit() {
        commandHandler?.quit()
    }
}

@MainActor
public final class MenuBarStatusItemController {
    private let statusItem: NSStatusItem
    private let viewModel: MenuBarStatusViewModel
    private let dropPanelController: MenuBarDropPanelController

    public init(viewModel: MenuBarStatusViewModel, statusBar: NSStatusBar = .system) {
        self.viewModel = viewModel
        dropPanelController = MenuBarDropPanelController(viewModel: viewModel)
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        viewModel.onChange = { [weak self] _ in
            self?.refresh()
        }
        refresh()
        dropPanelController.startDragMonitoring(anchorButton: statusItem.button)
    }

    public func refresh() {
        configureButton()
        statusItem.menu = makeMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: viewModel.systemImageName,
            accessibilityDescription: viewModel.statusTitle
        )
        button.toolTip = viewModel.statusTitle
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: viewModel.statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Open Workspace", action: #selector(openWorkspace), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: viewModel.pauseResumeTitle, action: #selector(togglePauseResume), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Recent Activity", action: #selector(showRecentActivity), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Quick Search", action: #selector(focusQuickSearch), keyEquivalent: "f"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Bipbox", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        return menu
    }

    @objc private func openWorkspace() {
        viewModel.openWorkspace()
    }

    @objc private func togglePauseResume() {
        viewModel.togglePauseResume()
    }

    @objc private func showRecentActivity() {
        viewModel.showRecentActivity()
    }

    @objc private func focusQuickSearch() {
        viewModel.focusQuickSearch()
    }

    @objc private func quit() {
        viewModel.quit()
    }
}

@MainActor
private final class MenuBarDropPanelController {
    private let viewModel: MenuBarStatusViewModel
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private weak var anchorButton: NSStatusBarButton?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?

    init(viewModel: MenuBarStatusViewModel) {
        self.viewModel = viewModel
    }

    func startDragMonitoring(anchorButton: NSStatusBarButton?) {
        self.anchorButton = anchorButton
        guard globalDragMonitor == nil, localDragMonitor == nil else {
            return
        }

        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showIfDraggingNearMenuBar()
            }
        }
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.showIfDraggingNearMenuBar()
            return event
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleHide()
            }
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.scheduleHide()
            return event
        }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        hideWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel

        if let button, let window = button.window {
            let buttonFrameInScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
            let panelSize = panel.frame.size
            let origin = NSPoint(
                x: buttonFrameInScreen.midX - panelSize.width / 2,
                y: buttonFrameInScreen.minY - panelSize.height - 8
            )
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
    }

    func showBelowMenuBar(on screen: NSScreen) {
        hideWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel

        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - panelSize.height - 8
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
    }

    private func showIfDraggingNearMenuBar() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return
        }

        let distanceFromTop = screen.frame.maxY - mouseLocation.y
        guard distanceFromTop >= 0, distanceFromTop <= 96 else {
            return
        }

        showBelowMenuBar(on: screen)
    }

    private func makePanel() -> NSPanel {
        let contentView = MenuBarInboxDropView { [weak self] urls in
            self?.hide()
            self?.viewModel.submitDroppedFileURLs(urls)
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 132),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = contentView
        return panel
    }
}

private final class MenuBarInboxDropView: NSView {
    private let onDrop: ([URL]) -> Void
    private var isTargeted = false {
        didSet {
            needsDisplay = true
        }
    }

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else {
            return []
        }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else {
            return false
        }
        isTargeted = false
        onDrop(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 8, dy: 8)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        path.fill()

        (isTargeted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isTargeted ? 2 : 1
        path.stroke()

        drawText(in: rect)
    }

    private func drawText(in rect: NSRect) {
        let title = "Drop into Bipbox"
        let subtitle = "Release to organize files or folders."
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        NSAttributedString(string: title, attributes: titleAttributes)
            .draw(in: NSRect(x: rect.minX + 16, y: rect.midY + 4, width: rect.width - 32, height: 24))
        NSAttributedString(string: subtitle, attributes: subtitleAttributes)
            .draw(in: NSRect(x: rect.minX + 16, y: rect.midY - 22, width: rect.width - 32, height: 18))
    }
}

@MainActor
private func fileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]
    return draggingInfo.draggingPasteboard
        .readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
}
