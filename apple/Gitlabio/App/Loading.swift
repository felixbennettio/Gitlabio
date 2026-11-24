import SwiftUI
import Observation
import GitLabCore

/// Loads a single value with loading / error / content states.
@MainActor @Observable
final class Loader<Value> {
    private(set) var value: Value?
    private(set) var error: Error?
    private(set) var isLoading = false
    private let fetch: () async throws -> Value

    init(_ fetch: @escaping () async throws -> Value) { self.fetch = fetch }

    func load(force: Bool = false) async {
        guard force || (value == nil && !isLoading) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            value = try await fetch()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    func set(_ value: Value) { self.value = value }
}

/// Paginated list loading with refresh and infinite scroll.
@MainActor @Observable
final class PagedLoader<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    private(set) var error: Error?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var total: Int?
    private var next: Int? = 1
    private var fetch: (Int) async throws -> Page<Item>
    private var generation = 0

    init(_ fetch: @escaping (Int) async throws -> Page<Item>) { self.fetch = fetch }

    var canLoadMore: Bool { next != nil && !isLoading && error == nil }

    func replaceFetch(_ fetch: @escaping (Int) async throws -> Page<Item>) {
        self.fetch = fetch
        generation += 1
        items = []
        next = 1
        hasLoaded = false
        error = nil
        isLoading = false
    }

    func loadFirst() async {
        guard !hasLoaded, !isLoading else { return }
        await load(page: 1)
    }

    func refresh() async {
        await load(page: 1)
    }

    func loadMore() async {
        guard let next, !isLoading else { return }
        await load(page: next)
    }

    func loadMoreIfNeeded(_ item: Item) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 5 else { return }
        await loadMore()
    }

    func remove(where predicate: (Item) -> Bool) { items.removeAll(where: predicate) }

    func update(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    }

    private func load(page: Int) async {
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let result = try await fetch(page)
            guard current == generation else { return }
            items = page == 1 ? result.items : items + result.items.filter { new in !items.contains { $0.id == new.id } }
            next = result.next
            total = result.total
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            guard current == generation else { return }
            self.error = error
            hasLoaded = true
        }
    }
}

/// Renders a `Loader`'s states around content.
struct LoadingContent<Value, Content: View>: View {
    let loader: Loader<Value>
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        Group {
            if let value = loader.value {
                content(value)
            } else if let error = loader.error {
                ErrorStateView(error: error) { await loader.load(force: true) }
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loader.load() }
    }
}

/// Footer row for paged lists: spinner, error with retry, or nothing.
struct PagingFooter<Item: Identifiable & Sendable>: View {
    let loader: PagedLoader<Item>

    var body: some View {
        if loader.isLoading && loader.hasLoaded {
            HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
        } else if let error = loader.error, !loader.items.isEmpty {
            VStack(spacing: 8) {
                Text(error.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                Button("重试") { Task { await loader.loadMore() } }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
}

/// A standard list state overlay for paged loaders.
struct PagedStateOverlay<Item: Identifiable & Sendable>: View {
    let loader: PagedLoader<Item>
    let emptyTitle: String
    let emptySymbol: String
    var emptyMessage: String?

    var body: some View {
        if loader.items.isEmpty {
            if !loader.hasLoaded || (loader.isLoading && loader.error == nil) {
                ProgressView().controlSize(.large)
            } else if let error = loader.error {
                ErrorStateView(error: error) { await loader.refresh() }
            } else {
                EmptyStateView(title: emptyTitle, symbol: emptySymbol, message: emptyMessage)
            }
        }
    }
}

/// Runs a mutating action, tracking busy state and surfacing errors as an alert.
@MainActor @Observable
final class ActionRunner {
    var isRunning = false
    var errorMessage: String?
    var showsError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func run(_ action: @escaping () async throws -> Void) {
        guard !isRunning else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            do { try await action(); Haptics.success() }
            catch is CancellationError {}
            catch { errorMessage = error.localizedDescription; Haptics.warning() }
        }
    }
}

extension View {
    func actionErrors(_ runner: ActionRunner) -> some View {
        alert("操作失败", isPresented: Binding(get: { runner.showsError }, set: { runner.showsError = $0 })) {
            Button("好") {}
        } message: {
            Text(runner.errorMessage ?? "")
        }
    }
}
