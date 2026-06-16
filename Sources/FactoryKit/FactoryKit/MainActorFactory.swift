//
// MainActorFactory.swift
// FactoryKit
//
// A Factory variant for dependencies whose construction must happen on the
// main actor (for example a `@MainActor` view model or service).
//

import Foundation

/// A Factory whose builder closure is main-actor isolated and is always invoked
/// on the main actor, no matter where resolution is requested from.
///
/// The container accessor itself stays nonisolated — its isolation would be
/// meaningless, since container properties are nonisolated. What matters is that
/// the builder runs on the main actor, which the `@MainActor` closure parameter
/// guarantees:
///
/// ```swift
/// extension Container {
///     var manager: MainActorFactory<MainActorManager> {
///         self { .init() }   // .init() is @MainActor; the accessor need not be
///     }
/// }
/// ```
///
/// Resolution is overloaded on the caller's isolation:
/// - From the main actor it is synchronous — no `await`, no hop.
/// - From any other context it is `async` and hops to the main actor first;
///   this requires `T: Sendable`, which `@MainActor` types satisfy implicitly.
///
/// All standard scope and registration modifiers are supported and delegate to
/// an underlying ``Factory``, so scope caching, context overrides, and resets
/// behave exactly as they do for a normal factory.
public nonisolated struct MainActorFactory<T: Sendable> {

    /// The underlying Factory. Resolve it only on the main actor — that is the
    /// contract this type enforces through its resolution overloads.
    internal var factory: Factory<T>

    /// Creates a `MainActorFactory`. The `builder` is main-actor isolated, so it
    /// may construct main-actor-isolated types even from a nonisolated accessor.
    public init(_ container: ManagedContainer, key: StaticString = #function, _ builder: @escaping @MainActor () -> T) {
        self.factory = Factory(container, key: key, Self.trampoline(builder))
    }

    /// Synchronous resolution, available when the caller is already on the main
    /// actor.
    @MainActor
    public func callAsFunction() -> T {
        factory()
    }

    /// Asynchronous resolution for callers off the main actor; hops to the main
    /// actor to build (and to return a cached instance) before returning.
    public func callAsFunction() async -> T {
        await MainActor.run { factory() }
    }

    /// Unsugared synchronous resolution.
    @MainActor
    public func resolve() -> T {
        factory.resolve()
    }

    /// Unsugared asynchronous resolution.
    public func resolve() async -> T {
        await MainActor.run { factory.resolve() }
    }

    // MARK: - Modifiers

    @discardableResult
    public func scope(_ scope: Scope) -> Self {
        _ = factory.scope(scope)
        return self
    }

    public var cached: Self {
        _ = factory.cached
        return self
    }

    public var shared: Self {
        _ = factory.shared
        return self
    }

    public var singleton: Self {
        _ = factory.singleton
        return self
    }

    /// Registers a new main-actor builder, overriding the original.
    @discardableResult
    public func register(factory builder: @escaping @MainActor () -> T) -> Self {
        _ = factory.register(factory: Self.trampoline(builder))
        return self
    }

    /// Registers a main-actor builder used only in SwiftUI previews.
    @discardableResult
    public func onPreview(factory builder: @escaping @MainActor () -> T) -> Self {
        _ = factory.onPreview(factory: Self.trampoline(builder))
        return self
    }

    /// Registers a main-actor builder used only while testing.
    @discardableResult
    public func onTest(factory builder: @escaping @MainActor () -> T) -> Self {
        _ = factory.onTest(factory: Self.trampoline(builder))
        return self
    }

    /// Resets the factory's registrations and/or scope caches.
    @discardableResult
    public func reset(_ options: FactoryResetOptions = .all) -> Self {
        _ = factory.reset(options)
        return self
    }

    /// Wraps a main-actor builder in a nonisolated `@Sendable` closure for
    /// storage in the underlying `Factory`. Resolution always invokes the
    /// underlying factory on the main actor (the sync path is `@MainActor`; the
    /// async path hops first), so `assumeIsolated` never trips.
    private static func trampoline(_ builder: @escaping @MainActor () -> T) -> @Sendable () -> T {
        { MainActor.assumeIsolated { builder() } }
    }
}

// SAFETY: the only stored member is an underlying Factory, which is itself
// @unchecked Sendable when T is Sendable.
extension MainActorFactory: @unchecked Sendable {}

// MARK: - Container sugar

public extension ManagedContainer {
    /// Syntactic sugar that creates a properly bound ``MainActorFactory`` from a
    /// main-actor-isolated builder closure.
    func callAsFunction<T>(
        key: StaticString = #function,
        _ builder: @escaping @MainActor () -> T
    ) -> MainActorFactory<T> {
        MainActorFactory(self, key: key, builder)
    }
}
