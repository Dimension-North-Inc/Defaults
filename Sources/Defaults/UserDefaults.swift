//
//  UserDefaults.swift
//  Defaults
//
//  Created by Mark Onyschuk on 11/4/24.
//  Copyright © 2024 Dimension North Inc. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - DefaultStore
/// Enum representing storage types for default values.
/// Supports both local `UserDefaults` and `NSUbiquitousKeyValueStore` for cloud synchronization.
public enum DefaultStore {
    case local(UserDefaults)
    case cloud(NSUbiquitousKeyValueStore)
}

extension DefaultStore {
    
    /// Returns a .local store associated with app group `identifier`.
    ///
    /// - Parameter identifier: a registered app group identifier
    /// - Returns: a group local, or `.standard` store if the group is invalid
    public static func group(_ identifier: String) -> Self {
        return .local(
            UserDefaults(suiteName: identifier) ?? .standard
        )
    }

    /// Retrieves the stored object for the specified key.
    public func object(forKey key: String) -> Any? {
        switch self {
        case .local(let defaults):
            return defaults.object(forKey: key)
        case .cloud(let store):
            return store.object(forKey: key)
        }
    }
    
    /// Sets a value for the specified key.
    public func set(_ value: Any?, forKey key: String) {
        switch self {
        case .local(let defaults):
            defaults.set(value, forKey: key)
        case .cloud(let store):
            store.set(value, forKey: key)
        }
    }
    
    /// Removes the object for the specified key.
    public func removeObject(forKey key: String) {
        switch self {
        case .local(let defaults):
            defaults.removeObject(forKey: key)
        case .cloud(let store):
            store.removeObject(forKey: key)
        }
    }
}

// MARK: - DefaultKey
/// Represents a key for storing a value in `DefaultStore`, along with its default value and optional validation.
///
/// The `validator` closure allows you to transform or constrain values before they are stored.
/// This is useful for clamping numeric ranges, normalizing strings, or applying other business rules.
///
/// ## Examples
///
/// Basic key with no validation:
/// ```swift
/// DefaultKey("username", value: "")
/// ```
///
/// Clamping a double value between 0 and 1:
/// ```swift
/// DefaultKey(
///     "nsfwThreshold",
///     value: 0.5,
///     validate: { max(0.0, min(1.0, \$0)) }
/// )
/// ```
///
/// Normalizing string input:
/// ```swift
/// DefaultKey(
///     "email",
///     value: "",
///     validate: { \$0.lowercased().trimmingCharacters(in: .whitespaces) }
/// )
/// ```
public struct DefaultKey<Value: Codable & Equatable> {
    public let key: String
    public let value: Value
    public let validate: (Value) -> Value

    public init(_ key: String, value: Value, validate: @escaping (Value) -> Value = { $0 }) {
        self.key = key
        self.value = value
        self.validate = validate
    }
}

// MARK: - DefaultKeys
/// Namespace for defining all keys used in the application.
public struct DefaultKeys: Sendable {}

/// Extension to define individual keys for user defaults.
public extension DefaultKeys {
    /// Indicates whether NSFW content is enabled.
    var useNSFW: DefaultKey<Bool> {
        DefaultKey("useNSFW", value: true)
    }

    /// Indicates whether all NSFW results are filtered.
    var filtersAllNSFWResults: DefaultKey<Bool> {
        DefaultKey("filtersAllNSFWResults", value: false)
    }

    /// Number of columns in the gallery grid.
    var gridColumns: DefaultKey<Int> {
        DefaultKey("gridColumns", value: 4)
    }
}


// MARK: - ObservableDefaultValue

@MainActor
public protocol ObservableDefault<T> {
    associatedtype T

    /// Registers a closure to be called whenever the value changes.
    /// - Parameter perform: A closure that receives the new value.
    func onChange(perform: @escaping (T) -> Void)
}

/// An observable wrapper for managing values stored in `DefaultStore`.
/// Updates are published to SwiftUI views via the `@Published` property wrapper.
@MainActor
public final class ObservableDefaultValue<T: Codable & Equatable>: NSObject, ObservableObject, ObservableDefault {
    private let key: DefaultKey<T>
    private let storage: DefaultStore
    private var callbacks: [(T) -> Void] = []

    @Published public private(set) var value: T

    public init(key: DefaultKey<T>, storage: DefaultStore = .local(.standard)) {
        self.key = key
        self.storage = storage

        if let data = storage.object(forKey: key.key) as? Data,
           let decodedValue = try? JSONDecoder().decode(T.self, from: data) {
            self.value = decodedValue
        } else {
            self.value = key.value
        }

        super.init()

        // Observe changes in storage
        switch storage {
        case .local:
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleExternalChange),
                name: UserDefaults.didChangeNotification,
                object: nil
            )
        case .cloud(let store):
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleExternalChange),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store
            )
        }
    }

    @MainActor
    public func setValue(_ newValue: T) {
        let validated = key.validate(newValue)
        guard validated != value else { return }

        value = validated

        if let encoded = try? JSONEncoder().encode(value) {
            storage.set(encoded, forKey: key.key)
        } else {
            storage.removeObject(forKey: key.key)
        }
        notifyCallbacks(value)
    }
    
    public func onChange(perform: @escaping (T) -> Void) {
        callbacks.append(perform)
    }

    @MainActor
    private func notifyCallbacks(_ newValue: T) {
        callbacks.forEach { $0(newValue) }
    }

    // `nonisolated` so the @objc notification thunk can be entered from any
    // thread — UserDefaults/ubiquitous-store change notifications are delivered
    // on whatever thread posts them. The body then hops to the main actor, since
    // synchronizeWithStorage touches @MainActor state and calling it off-main is a
    // fatal executor trap on current runtimes.
    @objc dynamic private nonisolated func handleExternalChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.synchronizeWithStorage()
        }
    }

    @MainActor
    private func synchronizeWithStorage() {
        if let data = storage.object(forKey: key.key) as? Data,
           let newValue = try? JSONDecoder().decode(T.self, from: data),
           newValue != value {
            value = newValue
            notifyCallbacks(newValue)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}


// MARK: - Default Property Wrapper
/// A property wrapper for use in SwiftUI views. Automatically observes changes to the stored value.
@MainActor
@propertyWrapper
public struct Default<T: Codable & Equatable>: DynamicProperty {
    @StateObject private var store: ObservableDefaultValue<T>

    /// Initializes the property wrapper.
    /// - Parameters:
    ///   - keyPath: The key to associate with this property.
    ///   - storage: The storage type, either local or cloud-based.
    public init(_ keyPath: KeyPath<DefaultKeys, DefaultKey<T>>, storage: DefaultStore = .local(.standard)) {
        let key = DefaultKeys()[keyPath: keyPath]
        _store = StateObject(wrappedValue: ObservableDefaultValue(key: key, storage: storage))
    }

    /// The wrapped value.
    public var wrappedValue: T {
        get { store.value }
        nonmutating set { store.setValue(newValue) }
    }

    /// A `Binding` to the stored value for use in SwiftUI views.
    public var projectedValue: Binding<T> {
        Binding(
            get: { self.store.value },
            set: { self.store.setValue($0) }
        )
    }
}

// MARK: - DefaultValue Property Wrapper
/// A property wrapper for non-SwiftUI contexts, providing direct access to the observable store.
@MainActor
@propertyWrapper
public struct DefaultValue<T: Codable & Equatable> {
    private var store: ObservableDefaultValue<T>

    public init(_ keyPath: KeyPath<DefaultKeys, DefaultKey<T>>, storage: DefaultStore = .local(.standard)) {
        let key = DefaultKeys()[keyPath: keyPath]
        self.store = ObservableDefaultValue(key: key, storage: storage)
    }

    public var wrappedValue: T {
        get { store.value }
        set { store.setValue(newValue) }
    }

    public var projectedValue: some ObservableDefault<T> {
        store
    }
}

