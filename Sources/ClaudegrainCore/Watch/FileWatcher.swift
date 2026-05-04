import Foundation
import CoreServices

/// Wraps FSEventStream for watching a directory tree.
/// Emits the set of changed file paths via the callback. Coalesced ~250ms by FSEvents.
public final class FileWatcher {
    public typealias Callback = @Sendable ([String]) -> Void

    private let queue: DispatchQueue
    private var stream: FSEventStreamRef?
    private let callback: Callback

    public init(queue: DispatchQueue = DispatchQueue(label: "claudegrain.fsevents", qos: .utility),
                callback: @escaping Callback) {
        self.queue = queue
        self.callback = callback
    }

    public func start(paths: [String]) {
        stop()
        let info = Unmanaged.passRetained(self).toOpaque()
        var context = FSEventStreamContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        let pathsCF = paths as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, _, _ in
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info!).takeUnretainedValue()
                // With kFSEventStreamCreateFlagUseCFTypes, paths is a CFArray of CFString.
                let cfArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue()
                let pathsArray = (cfArray as? [String]) ?? []
                watcher.callback(pathsArray)
            },
            &context,
            pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            Unmanaged<FileWatcher>.fromOpaque(info).release()
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
