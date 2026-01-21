//
//  RingBuffer.swift
//  PirateRadio
//
//  Thread-safe ring buffer for IQ data streaming
//

import Foundation

/// Thread-safe ring buffer for streaming IQ data between producer and consumer threads
final class RingBuffer<T> {
    // MARK: - Properties

    private var buffer: [T]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0

    private let capacity: Int
    private let lock = NSLock()
    private let dataAvailable = NSCondition()
    private let spaceAvailable = NSCondition()

    private var isClosed = false

    // MARK: - Initialization

    /// Creates a ring buffer with the specified capacity
    /// - Parameters:
    ///   - capacity: Maximum number of elements the buffer can hold
    ///   - defaultValue: Default value to initialize buffer elements
    init(capacity: Int, defaultValue: T) {
        self.capacity = capacity
        self.buffer = Array(repeating: defaultValue, count: capacity)
    }

    // MARK: - Public Properties

    /// Current number of elements in the buffer
    var currentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Whether the buffer is empty
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count == 0
    }

    /// Whether the buffer is full
    var isFull: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count == capacity
    }

    /// Available space for writing
    var availableSpace: Int {
        lock.lock()
        defer { lock.unlock() }
        return capacity - count
    }

    /// Available data for reading
    var availableData: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    // MARK: - Write Operations

    /// Writes elements to the buffer, blocking if full
    /// - Parameter elements: Array of elements to write
    /// - Returns: Number of elements written (0 if closed)
    @discardableResult
    func write(_ elements: [T]) -> Int {
        guard !elements.isEmpty else { return 0 }

        lock.lock()

        // Wait for space if buffer is full
        while count == capacity && !isClosed {
            lock.unlock()
            spaceAvailable.lock()
            spaceAvailable.wait()
            spaceAvailable.unlock()
            lock.lock()
        }

        if isClosed {
            lock.unlock()
            return 0
        }

        // Calculate how many elements we can write
        let elementsToWrite = min(elements.count, capacity - count)

        for i in 0..<elementsToWrite {
            buffer[writeIndex] = elements[i]
            writeIndex = (writeIndex + 1) % capacity
        }

        count += elementsToWrite

        lock.unlock()

        // Signal that data is available
        dataAvailable.lock()
        dataAvailable.broadcast()
        dataAvailable.unlock()

        // If we couldn't write all elements, recursively write the rest
        if elementsToWrite < elements.count {
            let remaining = Array(elements[elementsToWrite...])
            return elementsToWrite + write(remaining)
        }

        return elementsToWrite
    }

    /// Writes elements without blocking, returns immediately if no space
    /// - Parameter elements: Array of elements to write
    /// - Returns: Number of elements actually written
    @discardableResult
    func writeNonBlocking(_ elements: [T]) -> Int {
        guard !elements.isEmpty else { return 0 }

        lock.lock()

        if isClosed {
            lock.unlock()
            return 0
        }

        let elementsToWrite = min(elements.count, capacity - count)

        for i in 0..<elementsToWrite {
            buffer[writeIndex] = elements[i]
            writeIndex = (writeIndex + 1) % capacity
        }

        count += elementsToWrite

        lock.unlock()

        if elementsToWrite > 0 {
            dataAvailable.lock()
            dataAvailable.broadcast()
            dataAvailable.unlock()
        }

        return elementsToWrite
    }

    // MARK: - Read Operations

    /// Reads elements from the buffer, blocking if empty
    /// - Parameter maxCount: Maximum number of elements to read
    /// - Returns: Array of elements read (empty if closed and no data)
    func read(maxCount: Int) -> [T] {
        guard maxCount > 0 else { return [] }

        lock.lock()

        // Wait for data if buffer is empty
        while count == 0 && !isClosed {
            lock.unlock()
            dataAvailable.lock()
            dataAvailable.wait()
            dataAvailable.unlock()
            lock.lock()
        }

        if count == 0 && isClosed {
            lock.unlock()
            return []
        }

        let elementsToRead = min(maxCount, count)
        var result = [T]()
        result.reserveCapacity(elementsToRead)

        for _ in 0..<elementsToRead {
            result.append(buffer[readIndex])
            readIndex = (readIndex + 1) % capacity
        }

        count -= elementsToRead

        lock.unlock()

        // Signal that space is available
        spaceAvailable.lock()
        spaceAvailable.broadcast()
        spaceAvailable.unlock()

        return result
    }

    /// Reads elements without blocking, returns immediately if no data
    /// - Parameter maxCount: Maximum number of elements to read
    /// - Returns: Array of elements read (may be empty)
    func readNonBlocking(maxCount: Int) -> [T] {
        guard maxCount > 0 else { return [] }

        lock.lock()

        let elementsToRead = min(maxCount, count)

        if elementsToRead == 0 {
            lock.unlock()
            return []
        }

        var result = [T]()
        result.reserveCapacity(elementsToRead)

        for _ in 0..<elementsToRead {
            result.append(buffer[readIndex])
            readIndex = (readIndex + 1) % capacity
        }

        count -= elementsToRead

        lock.unlock()

        spaceAvailable.lock()
        spaceAvailable.broadcast()
        spaceAvailable.unlock()

        return result
    }

    /// Reads elements directly into a raw buffer pointer (for C interop)
    /// - Parameters:
    ///   - destination: Pointer to write elements to
    ///   - maxCount: Maximum number of elements to read
    /// - Returns: Number of elements read
    func readInto(_ destination: UnsafeMutablePointer<T>, maxCount: Int) -> Int {
        guard maxCount > 0 else { return 0 }

        lock.lock()

        // Wait for data if buffer is empty
        while count == 0 && !isClosed {
            lock.unlock()
            dataAvailable.lock()
            dataAvailable.wait()
            dataAvailable.unlock()
            lock.lock()
        }

        if count == 0 && isClosed {
            lock.unlock()
            return 0
        }

        let elementsToRead = min(maxCount, count)

        for i in 0..<elementsToRead {
            destination[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }

        count -= elementsToRead

        lock.unlock()

        spaceAvailable.lock()
        spaceAvailable.broadcast()
        spaceAvailable.unlock()

        return elementsToRead
    }

    // MARK: - Control Operations

    /// Closes the buffer, waking up any waiting readers/writers
    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()

        // Wake up all waiting threads
        dataAvailable.lock()
        dataAvailable.broadcast()
        dataAvailable.unlock()

        spaceAvailable.lock()
        spaceAvailable.broadcast()
        spaceAvailable.unlock()
    }

    /// Resets the buffer to its initial state
    func reset() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        count = 0
        isClosed = false
        lock.unlock()
    }

    /// Whether the buffer has been closed
    var closed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }
}

// MARK: - IQ Buffer Type Alias

/// Specialized ring buffer for Int8 IQ data
typealias IQRingBuffer = RingBuffer<Int8>

extension IQRingBuffer {
    /// Creates an IQ ring buffer with the specified capacity in bytes
    /// - Parameter capacityBytes: Capacity in bytes (each I/Q pair is 2 bytes)
    convenience init(capacityBytes: Int) {
        self.init(capacity: capacityBytes, defaultValue: 0)
    }
}
