import SwiftUI

// MARK: - ViewModel

@MainActor
class GIFViewModel: ObservableObject {
    @Published var gifs: [KlipyGIF] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private var searchTask: Task<Void, Never>?

    func loadTrending() {
        searchTask?.cancel()
        isLoading = true
        errorMessage = nil
        Task {
            do { gifs = try await KlipyService.shared.trending() }
            catch { errorMessage = "Couldn't load GIFs. Check your API key." }
            isLoading = false
        }
    }

    func search(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else { loadTrending(); return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isLoading = true
            errorMessage = nil
            do { gifs = try await KlipyService.shared.search(query: query) }
            catch { if !Task.isCancelled { errorMessage = "Search failed." } }
            isLoading = false
        }
    }
}

// MARK: - Shared brand color

extension Color {
    /// Dark purple sampled from the icon's corner gradient — blends the icon edge seamlessly.
    static let brandPurple = Color(red: 0.13, green: 0.03, blue: 0.28)
}

// MARK: - Frosted-glass background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Main view

struct ContentView: View {
    let onHover: (KlipyGIF?) -> Void

    @StateObject private var viewModel = GIFViewModel()
    @State private var hoveredGIF: KlipyGIF? = nil
    @State private var hasKey = KeychainHelper.hasKey

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 5)

    var body: some View {
        Group {
            if hasKey {
                gifPicker
            } else {
                OnboardingView {
                    hasKey = true
                    viewModel.loadTrending()
                }
            }
        }
        .background(
            ZStack {
                VisualEffectBackground()
                Color.brandPurple.opacity(0.18)
            }
        )
        // Re-check on every open in case key was cleared from right-click menu
        .onAppear { hasKey = KeychainHelper.hasKey }
        .onReceive(NotificationCenter.default.publisher(for: .reGIFtAPIKeyCleared)) { _ in
            hasKey = false
        }
    }

    private var gifPicker: some View {
        VStack(spacing: 0) {
            header
            gifGrid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hoveredGIF?.id) { _ in onHover(hoveredGIF) }
        .onAppear {
            if viewModel.gifs.isEmpty { viewModel.loadTrending() }
        }
    }

    // MARK: Header — icon + search bar + section label

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // App icon as in-window branding — load from asset catalog for crisp rendering
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 64, height: 64)
                    .mask(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white, location: 0.58),
                                .init(color: .clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .medium))
                    TextField("Search GIFs…", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onChange(of: viewModel.searchText) { value in
                            viewModel.search(query: value)
                        }
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                            viewModel.loadTrending()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

                // Section label
                HStack {
                    Text(viewModel.searchText.isEmpty ? "TRENDING" : "RESULTS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.55))
                        .tracking(1)
                    Spacer()
                    ZStack {
                        if viewModel.isLoading { ProgressView().scaleEffect(0.6) }
                    }
                    .frame(width: 20, height: 20)
                }
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: GIF grid

    @ViewBuilder
    private var gifGrid: some View {
        if viewModel.gifs.isEmpty && !viewModel.isLoading {
            VStack(spacing: 10) {
                Image(systemName: viewModel.errorMessage != nil
                      ? "exclamationmark.triangle" : "photo.on.rectangle")
                    .font(.largeTitle).foregroundColor(.secondary)
                Text(viewModel.errorMessage ?? "No results").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 1) {
                    ForEach(viewModel.gifs) { gif in
                        GIFCellView(gif: gif, hoveredGIF: $hoveredGIF)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Onboarding view

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 8) {
                Text("Welcome to reGIFt")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("A free Klipy API key is needed to search and display GIFs.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Link("Get a free key at klipy.com/api-overview →",
                 destination: URL(string: "https://klipy.com/api-overview")!)
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.6, green: 0.5, blue: 1.0))

            VStack(spacing: 6) {
                TextField("Paste your API key here", text: $apiKey)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                }
            }
            .padding(.horizontal, 4)

            Button(isValidating ? "Checking…" : "Save Key") {
                validate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func validate() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isValidating = true
        errorMessage = nil
        Task {
            let url = URL(string: "https://api.klipy.com/api/v1/\(key)/gifs/trending?per_page=1")!
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    KeychainHelper.save(key)
                    await MainActor.run { onComplete() }
                } else {
                    await MainActor.run {
                        errorMessage = "Invalid key — please check and try again."
                        isValidating = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection failed — check your internet and try again."
                    isValidating = false
                }
            }
        }
    }
}

// MARK: - Preview panel view (lives in separate NSPanel)

struct PreviewPanelView: View {
    @EnvironmentObject var state: PreviewState
    private let titleHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if let gif = state.gif {
                    // Title above GIF — width matches the displayed image
                    if !gif.title.isEmpty {
                        let gifHeight = max(1, geo.size.height - titleHeight)
                        let imageWidth = max(1, min(geo.size.width, gifHeight * gif.thumbAspectRatio))
                        Text(gif.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: imageWidth, height: titleHeight)
                            .background(Color.black.opacity(0.72))
                            .frame(maxWidth: .infinity)
                    }

                    // GIF fills remaining space
                    GIFWebView(url: gif.gifURL ?? gif.thumbURL, fit: "contain")
                        .id(gif.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
