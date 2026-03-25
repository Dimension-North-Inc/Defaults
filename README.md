# Defaults

<a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat" alt="Swift 6.0"></a>
<img src="https://img.shields.io/badge/platforms-macOS%2011+|iOS%2014+-blue.svg?style=flat" alt="Platforms">
<a href="https://github.com/apple/swift-package-manager"><img src="https://img.shields.io/badge/SPM-compatible-green.svg?style=flat" alt="SPM"></a>

A type-safe, centralized alternative to SwiftUI's `@AppStorage` for managing user defaults with compile-time safety, key reuse, and built-in cloud synchronization.

## Why Defaults?

### The Problem with `@AppStorage`

SwiftUI's `@AppStorage` is stringly typed—you define keys as raw strings everywhere you need them:

```swift
// View A
struct SettingsView: View {
    @AppStorage("useNSFW") private var useNSFW = true
    @AppStorage("gridColumns") private var gridColumns = 4
}

// View B - must retype strings, prone to typos
struct GalleryView: View {
    @AppStorage("useNSFW") private var useNSFW = true  // retyped
    @AppStorage("gridColumns") private var gridColumns = 4  // retyped
}

// ViewModel C - same problem
class ContentViewModel: ObservableObject {
    @Published var useNSFW: Bool {
        didSet { UserDefaults.standard.set(useNSFW, forKey: "useNSFW") }
    }
}
```

This approach:
- **Duplicates string literals** across your codebase
- **Provides no compile-time safety**—misspelling a key compiles silently
- **Scatters default values** throughout views instead of centralizing them
- **Makes validation inconsistent**—each view can implement its own (or none)

### The Defaults Solution

Define your keys **once** with types, defaults, and optional validation:

```swift
// Keys.swift - Define all keys in one place
extension DefaultKeys {
    var useNSFW: DefaultKey<Bool> {
        DefaultKey(key: "useNSFW", default: true)
    }

    var gridColumns: DefaultKey<Int> {
        DefaultKey(key: "gridColumns", default: 4, validate: { max(1, min($0, 12)) })
    }
}
```

Then use them **everywhere** with full type safety:

```swift
struct SettingsView: View {
    @Default(\.useNSFW) private var useNSFW
    @Default(\.gridColumns) private var gridColumns
}

struct GalleryView: View {
    @Default(\.useNSFW) private var useNSFW
    @Default(\.gridColumns) private var gridColumns
}

class ContentViewModel: ObservableObject {
    @DefaultValue(\.useNSFW) var useNSFW: Bool
    @DefaultValue(\.gridColumns) var gridColumns: Int
}
```

**Benefits:**
- Keys defined **once**, used everywhere—single source of truth
- **Compile-time safety**—typos caught by the compiler
- **Centralized defaults**—change once, applies everywhere
- **Built-in validation**—optional `validate` closure transforms values on write
- **Cloud sync ready**—supports `NSUbiquitousKeyValueStore` out of the box

---

## `@Default` vs `@DefaultValue`

| Property Wrapper | Context | SwiftUI Integration | Purpose |
|------------------|---------|---------------------|---------|
| `@Default` | SwiftUI Views | Provides `Binding<T>` via `projectedValue` | For views that need to bind directly to controls like `Toggle` or `Slider` |
| `@DefaultValue` | ViewModels, Services, Non-Views | Provides `ObservableDefault<T>` via `projectedValue` | For programmatic access with `onChange` callbacks |

### `@Default` — For SwiftUI Views

Use in views where you need SwiftUI's `Binding` integration:

```swift
struct SettingsView: View {
    @Default(\.useNSFW) private var useNSFW
    @Default(\.gridColumns) private var gridColumns

    var body: some View {
        Form {
            Toggle("Show NSFW Content", isOn: $useNSFW)

            Stepper("Grid Columns: \(gridColumns)", value: $gridColumns, in: 1...12)
        }
    }
}
```

### `@DefaultValue` — For ViewModels & Non-Views

Use in view models or services where you need `onChange` callbacks:

```swift
class GalleryViewModel: ObservableObject {
    @DefaultValue(\.useNSFW) var useNSFW: Bool
    @DefaultValue(\.gridColumns) var gridColumns: Int

    init() {
        // React to changes via the projected value ($useNSFW)
        $useNSFW.onChange { newValue in
            self.filterContent()
        }
    }

    private func filterContent() {
        // Handle the change
    }
}
```

---

## Creating a New Default Key

### 1. Define the Key

Add to your `DefaultKeys` extension:

```swift
extension DefaultKeys {
    var mySetting: DefaultKey<Bool> {
        DefaultKey(key: "mySetting", default: false)
    }

    var username: DefaultKey<String> {
        DefaultKey(key: "username", default: "")
    }

    var threshold: DefaultKey<Double> {
        DefaultKey(
            key: "threshold",
            default: 0.5,
            validate: { max(0.0, min(1.0, $0)) }  // clamp to 0-1
        )
    }
}
```

### 2. Use in a SwiftUI View

```swift
struct ProfileView: View {
    @Default(\.username) private var username

    var body: some View {
        TextField("Username", text: $username)
    }
}
```

### 3. Use in a ViewModel

```swift
class ProfileViewModel: ObservableObject {
    @DefaultValue(\.username) var username: String

    func validate() -> Bool {
        return !username.isEmpty
    }
}
```

---

## Cloud Synchronization

Defaults supports `NSUbiquitousKeyValueStore` for automatic iCloud sync:

```swift
// Use cloud storage instead of local
@Default(\.mySetting, storage: .cloud(.ubiquitous)) private var mySetting

// Or with explicit store
@Default(\.mySetting, storage: .local(UserDefaults(suiteName: "group.com.app")!)) private var mySetting

// Using the group helper
@Default(\.mySetting, storage: .group("group.com.app")) private var mySetting
```

---

## Installation

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/your-org/Defaults.git", from: "1.0.0")
]
```

```swift
// Your project
.target(
    name: "YourTarget",
    dependencies: ["Defaults"]
)
```

---

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| macOS | 11.0 (Big Sur) |
| iOS | 14.0 |
| Swift | 6.0 |

---

## License

Copyright © 2024 Dimension North Inc. All rights reserved.
