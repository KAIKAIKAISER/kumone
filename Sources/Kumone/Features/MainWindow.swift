import SwiftUI

struct MainWindow: View {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var toasts: ToastCenter

    #if os(macOS)
    @StateObject private var artworkStore = NowPlayingArtworkStore()
    #endif
    @State private var selection: SidebarItem = .home
    @State private var path = NavigationPath()
    @State private var showLogin = false
    @State private var detailWidth: CGFloat = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var visibilityBeforeNowPlaying: NavigationSplitViewVisibility?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection, showLogin: $showLogin)
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.Layout.sidebarWidth, max: 280)
        } detail: {
            detailStack
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    detailWidth = width
                }
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .overlay(alignment: .trailing) {
            if settings.showMainWindowAmbientBackground, detailWidth > 0 {
                MainWindowAmbientBackground(
                    colors: artworkStore.colors,
                    intensity: settings.mainWindowAmbientBackgroundIntensity
                )
                    .frame(width: detailWidth)
            }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SearchFieldView { query in
                    path.append(Destination.search(query))
                }
            }
        }
        #if os(macOS)
        // Immersive now-playing page: hide the whole window toolbar
        // (sidebar toggle, navigation title, search field).
        .toolbar(player.showNowPlaying ? .hidden : .automatic, for: .windowToolbar)
        // Keep the single main window alive on Cmd+W / red button so the Dock
        // icon can always bring it back (#60/#63/#66/#70).
        .background(
            MainWindowConfigurator(
                showsAmbientBackground: settings.showMainWindowAmbientBackground,
                showsTitlebarAmbientBackground: !player.showNowPlaying,
                colors: artworkStore.colors,
                mainColumnWidth: detailWidth,
                intensity: settings.mainWindowAmbientBackgroundIntensity
            )
        )
        #endif
        .playerChrome(detailWidth: detailWidth)
        .environment(\.openLogin, { showLogin = true })
        #if os(macOS)
        .environmentObject(artworkStore)
        #endif
        .task {
#if os(macOS)
            // Keep this action in the app delegate: when the user closes the
            // last WindowGroup window, there is no view left to receive a
            // Dock reopen event directly.
            AppDelegate.shared?.openMainWindow = { openWindow(id: "main") }
            artworkStore.setArtworkNeeded(
                settings.showMainWindowAmbientBackground || player.showNowPlaying
            )
#endif
            DesktopLyricsController.shared.sync(with: settings.showDesktopLyrics)
            await account.bootstrap()
        }
        .onChange(of: settings.showDesktopLyrics) { _ in
            DesktopLyricsController.shared.sync(with: settings.showDesktopLyrics)
        }
        #if os(macOS)
        .onChange(of: settings.showMainWindowAmbientBackground) { _ in
            artworkStore.setArtworkNeeded(
                settings.showMainWindowAmbientBackground || player.showNowPlaying
            )
        }
        #endif
        // Collapse the sidebar while the immersive page is open: the split
        // view's divider keeps its resize-cursor rect active even underneath
        // an overlay, leaking the drag cursor onto the now-playing page (#6).
        .onChange(of: player.showNowPlaying) { _ in
            #if os(macOS)
            artworkStore.setArtworkNeeded(
                settings.showMainWindowAmbientBackground || player.showNowPlaying
            )
            #endif
            if player.showNowPlaying {
                visibilityBeforeNowPlaying = columnVisibility
                columnVisibility = .detailOnly
            } else {
                columnVisibility = visibilityBeforeNowPlaying ?? .all
                visibilityBeforeNowPlaying = nil
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet()
        }
        .overlay {
            if player.showNowPlaying {
                #if os(macOS)
                NowPlayingView()
                    .environmentObject(artworkStore)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                #else
                NowPlayingView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                #endif
            }
        }
        .overlay(alignment: .top) {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
        .animation(AppAnimation.smooth, value: player.showNowPlaying)
        .animation(.spring(duration: 0.3), value: toasts.current)
    }

    private var detailStack: some View {
        NavigationStack(path: $path) {
            rootView
                .playerContentInset()
                .appDestinations()
        }
        .onChange(of: selection) { _ in
            path = NavigationPath()
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch selection {
        case .home:
            HomeView()
        case .explore:
            ExploreView()
        case .fm:
            FMView()
        case .search:
            // iPad search entry: SearchView's `.searchable` bar surfaces in the
            // detail nav bar (the desktop toolbar search field doesn't render on
            // iPad). (#59)
            SearchView(query: "")
        case .likedSongs:
            if let playlist = account.likedSongsPlaylist {
                PlaylistDetailView(playlistID: playlist.id, isLikedList: true)
                    .id(playlist.id)
            } else {
                loginPrompt
            }
        case .daily:
            DailySongsView()
        case .recents:
            RecentsView()
        case .collections:
            CollectionsView()
        case .cloud:
            CloudView()
        case .playlist(let id):
            PlaylistDetailView(playlistID: id)
                .id(id)
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("登录后查看你喜欢的音乐")
                .font(.headline)
            Button("登录") { showLogin = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

#if os(macOS)
// MARK: - Main window configurator

/// Grabs the single main `NSWindow` once it exists and installs a close
/// interceptor: Cmd+W / the red button *hide* the window (`orderOut`) instead
/// of destroying the single-instance `Window` scene. Destroying the scene left
/// the app running with no way to reopen it (#60/#66/#70); hiding keeps the
/// SwiftUI scene fully alive so `AppDelegate.applicationShouldHandleReopen`
/// can front it again on a Dock click. Every other window-delegate callback is
/// forwarded untouched to SwiftUI's own delegate.
struct MainWindowConfigurator: NSViewRepresentable {
    let showsAmbientBackground: Bool
    let showsTitlebarAmbientBackground: Bool
    let colors: ArtworkColors
    let mainColumnWidth: CGFloat
    let intensity: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.requestAmbientBackgroundConfiguration(
                from: view,
                showsAmbientBackground: showsAmbientBackground,
                showsTitlebarAmbientBackground: showsTitlebarAmbientBackground,
                colors: colors,
                mainColumnWidth: mainColumnWidth,
                intensity: intensity
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.requestAmbientBackgroundConfiguration(
                from: nsView,
                showsAmbientBackground: showsAmbientBackground,
                showsTitlebarAmbientBackground: showsTitlebarAmbientBackground,
                colors: colors,
                mainColumnWidth: mainColumnWidth,
                intensity: intensity
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private(set) weak var window: NSWindow?
        private weak var forwardee: NSWindowDelegate?
        private var showsAmbientBackground = false
        private var showsTitlebarAmbientBackground = false
        private var titlebarWasTransparent: Bool?
        private var hadFullSizeContentView = false
        private var colors: ArtworkColors = .fallback
        private var mainColumnWidth: CGFloat = 0
        private var intensity: Double = 1
        private var titlebarMask: TitlebarMaskView?
        private weak var configurationHost: NSView?
        private var pendingAmbientConfiguration: AmbientConfiguration?
        private var hasScheduledAmbientConfiguration = false

        private struct AmbientConfiguration {
            let showsAmbientBackground: Bool
            let showsTitlebarAmbientBackground: Bool
            let colors: ArtworkColors
            let mainColumnWidth: CGFloat
            let intensity: Double
        }

        func attach(to window: NSWindow?) {
            guard let window, self.window == nil else { return }
            self.window = window
            window.isReleasedWhenClosed = false
            // Insert ourselves as the delegate, forwarding to whatever
            // delegate SwiftUI installed.
            if window.delegate !== self {
                forwardee = window.delegate
                window.delegate = self
            }
            AppDelegate.shared?.mainWindow = window
        }

        func requestAmbientBackgroundConfiguration(
            from host: NSView,
            showsAmbientBackground: Bool,
            showsTitlebarAmbientBackground: Bool,
            colors: ArtworkColors,
            mainColumnWidth: CGFloat,
            intensity: Double
        ) {
            configurationHost = host
            pendingAmbientConfiguration = AmbientConfiguration(
                showsAmbientBackground: showsAmbientBackground,
                showsTitlebarAmbientBackground: showsTitlebarAmbientBackground,
                colors: colors,
                mainColumnWidth: mainColumnWidth,
                intensity: intensity
            )
            guard !hasScheduledAmbientConfiguration else { return }
            hasScheduledAmbientConfiguration = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hasScheduledAmbientConfiguration = false
                guard let configuration = self.pendingAmbientConfiguration else { return }
                self.pendingAmbientConfiguration = nil
                self.attach(to: self.configurationHost?.window)
                self.configureAmbientBackground(
                    configuration.showsAmbientBackground,
                    showsTitlebarAmbientBackground: configuration.showsTitlebarAmbientBackground,
                    colors: configuration.colors,
                    mainColumnWidth: configuration.mainColumnWidth,
                    intensity: configuration.intensity
                )
            }
        }

        func configureAmbientBackground(
            _ showsAmbientBackground: Bool,
            showsTitlebarAmbientBackground: Bool,
            colors: ArtworkColors,
            mainColumnWidth: CGFloat,
            intensity: Double
        ) {
            self.showsTitlebarAmbientBackground = showsTitlebarAmbientBackground
            self.colors = colors
            self.mainColumnWidth = mainColumnWidth
            self.intensity = intensity
            guard let window else { return }

            guard self.showsAmbientBackground != showsAmbientBackground else {
                applyAmbientWindowAppearance()
                return
            }
            self.showsAmbientBackground = showsAmbientBackground

            if showsAmbientBackground {
                titlebarWasTransparent = window.titlebarAppearsTransparent
                hadFullSizeContentView = window.styleMask.contains(.fullSizeContentView)
                applyAmbientWindowAppearance()
            } else {
                window.titlebarAppearsTransparent = titlebarWasTransparent ?? false
                if hadFullSizeContentView {
                    window.styleMask.insert(.fullSizeContentView)
                } else {
                    window.styleMask.remove(.fullSizeContentView)
                }
                titlebarWasTransparent = nil
                removeTitlebarMask()
            }
        }

        func windowDidUpdate(_ notification: Notification) {
            applyAmbientWindowAppearance()
            forwardee?.windowDidUpdate?(notification)
        }

        private func applyAmbientWindowAppearance() {
            guard showsAmbientBackground, let window else { return }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            guard showsTitlebarAmbientBackground else {
                removeTitlebarMask()
                return
            }
            installTitlebarMask(in: window)
            layoutTitlebarMask(in: window)
        }

        private func installTitlebarMask(in window: NSWindow) {
            guard titlebarMask == nil, let contentView = window.contentView else { return }
            let mask = TitlebarMaskView()
            contentView.addSubview(mask, positioned: .above, relativeTo: nil)
            titlebarMask = mask
        }

        private func layoutTitlebarMask(in window: NSWindow) {
            guard let mask = titlebarMask, let contentView = window.contentView else { return }
            let width = min(max(mainColumnWidth, 0), contentView.bounds.width)
            guard width > 0 else {
                mask.isHidden = true
                return
            }

            let layoutRect = window.contentLayoutRect
            let titlebarHeight = contentView.bounds.height - layoutRect.height
            guard titlebarHeight > 0 else {
                mask.isHidden = true
                return
            }
            let y = contentView.isFlipped
                ? contentView.bounds.minY
                : contentView.bounds.maxY - titlebarHeight
            let frame = CGRect(
                x: contentView.bounds.maxX - width,
                y: y,
                width: width,
                height: titlebarHeight
            )

            if mask.frame != frame {
                mask.frame = frame
            }
            if mask.isHidden {
                mask.isHidden = false
            }
            mask.update(
                colors: colors,
                appearance: window.effectiveAppearance,
                intensity: intensity
            )
        }

        private func removeTitlebarMask() {
            titlebarMask?.removeFromSuperview()
            titlebarMask = nil
        }

        // Hide instead of close; keep the scene alive.
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }

        // Transparently forward every other delegate callback to SwiftUI.
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (forwardee?.responds(to: aSelector) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if forwardee?.responds(to: aSelector) == true { return forwardee }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

private final class TitlebarMaskView: NSView {
    private let gradientLayer = CAGradientLayer()
    private var appliedColors: ArtworkColors?
    private var appliedAppearanceName: NSAppearance.Name?
    private var appliedIntensity: Double?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(colors: ArtworkColors, appearance: NSAppearance, intensity: Double) {
        guard appliedColors != colors
                || appliedAppearanceName != appearance.name
                || appliedIntensity != intensity else {
            return
        }
        appliedColors = colors
        appliedAppearanceName = appearance.name
        appliedIntensity = intensity

        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let opacity = CGFloat(
            MainWindowAmbientOpacity.gradient(isDark: isDark, intensity: intensity)
        )
        let base = NSColor.windowBackgroundColor
        let primary = blended(NSColor(colors.primary), over: base, opacity: opacity)
        let secondary = blended(NSColor(colors.secondary), over: base, opacity: opacity)

        CATransaction.begin()
        CATransaction.setDisableActions(Platform.isReduceMotionEnabled)
        CATransaction.setAnimationDuration(0.6)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        gradientLayer.colors = [primary.cgColor, secondary.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        CATransaction.commit()
    }

    private func blended(_ color: NSColor, over base: NSColor, opacity: CGFloat) -> NSColor {
        let foreground = color.usingColorSpace(.extendedSRGB) ?? color
        let background = base.usingColorSpace(.extendedSRGB) ?? base
        return NSColor(
            red: background.redComponent + (foreground.redComponent - background.redComponent) * opacity,
            green: background.greenComponent + (foreground.greenComponent - background.greenComponent) * opacity,
            blue: background.blueComponent + (foreground.blueComponent - background.blueComponent) * opacity,
            alpha: 1
        )
    }
}
#endif

// MARK: - Search field

struct SearchFieldView: View {
    let onSubmit: (String) -> Void

    @State private var text = ""
    @State private var placeholder = "搜索音乐、歌手、专辑"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .frame(width: 168)
                .onSubmit {
                    let query = text.trimmingCharacters(in: .whitespaces)
                    let effective = query.isEmpty ? placeholderQuery : query
                    guard !effective.isEmpty else { return }
                    onSubmit(effective)
                    focused = false
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(focused ? 0.18 : 0.08), lineWidth: 1))
        .animation(AppAnimation.quick, value: focused)
        .task {
            if let keyword = try? await NeteaseAPI.searchDefaultKeyword(), !keyword.isEmpty {
                placeholder = keyword
                placeholderQuery = keyword
            }
        }
    }

    @State private var placeholderQuery = ""
}

// MARK: - Toast

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Text(toast.message)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .compatGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
