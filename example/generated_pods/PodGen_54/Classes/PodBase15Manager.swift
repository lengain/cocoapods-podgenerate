import Foundation

public final class PodBase15Manager {

    public static let shared = PodBase15Manager()

    private let queue = DispatchQueue(label: "com.example.PodBase15.manager")
    private var items: [String: Any] = [:]

    private init() {}

    public func setValue(_ value: Any, forKey key: String) {
        queue.sync { items[key] = value }
    }

    public func value(forKey key: String) -> Any? {
        return queue.sync { items[key] }
    }

    public func removeValue(forKey key: String) {
        queue.sync { items.removeValue(forKey: key) }
    }

    public var allKeys: [String] {
        return queue.sync { Array(items.keys) }
    }

    public var count: Int {
        return queue.sync { items.count }
    }

    public func clear() {
        queue.sync { items.removeAll() }
    }
}
