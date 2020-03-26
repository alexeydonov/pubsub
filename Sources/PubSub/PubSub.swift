//
//  File.swift
//  
//
//  Created by Alexey Donov on 24.03.2020.
//

import Foundation

// MARK: - Publisher

/// Publisher
public final class Publisher<Value> {

    public init() {
        
    }

    /// Publish value to subscriptions
    ///
    /// - Parameter value: Value to be published
    public func publish(_ value: Value) {
        lastValue = value
        for subscription in subscriptions {
            subscription.receive(value)
        }
    }

    /// Create a subscription that will receive published values
    ///
    /// - Parameter receiveLastValue: Indicates if the subscription should receive last published value immediately.
    /// - Returns: A new subscription
    public func subscribe(receiveLastValue: Bool = true) -> Subscription<Value> {
        let subscription = Subscription<Value>(publisher: self, upstream: nil, initialValue: receiveLastValue ? lastValue : nil)
        if receiveLastValue, let value = lastValue {
            subscription.receive(value)
        }

        subscriptions.append(subscription)

        return subscription
    }

    fileprivate func unsubscribe(_ subscription: Subscription<Value>) {
        subscriptions.removeAll { $0 === subscription }
    }

    private var lastValue: Value?

    private var subscriptions: [Subscription<Value>] = []

}

// MARK: - Subscription

/// Basic subscription that obly passes value to downstreams
public class Subscription<Value> {

    public func unsubscribe() {
        if let publisher = self.publisher {
            publisher.unsubscribe(self)
        }
        else if let upstream = self.upstream {
            upstream.unsubscribe()
        }
    }

    init(publisher: Publisher<Value>?, upstream: Subscription<Value>?, initialValue: Value?) {
        self.publisher = publisher
        self.upstream = upstream
        self.initialValue = initialValue

        if let value = initialValue {
            receive(value)
        }
    }

    fileprivate func receive(_ value: Value) {
        for downstream in downstreams {
            downstream.receive(value)
        }
    }

    fileprivate func handle(_ error: Error) {
        for downstream in downstreams {
            downstream.handle(error)
        }
    }

    private var initialValue: Value?
    private unowned var publisher: Publisher<Value>?
    private unowned var upstream: Subscription<Value>?

    private var downstreams: [Subscription<Value>] = []

}

// MARK: - ConsumeSubscription

class ConsumeSubscription<Value>: Subscription<Value> {
    init(publisher: Publisher<Value>?, upstream: Subscription<Value>?, initialValue: Value?, consumer: @escaping (Value) throws -> Void) {
        self.consumer = consumer

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    private var consumer: (Value) throws -> Void

    override fileprivate func receive(_ value: Value) {
        do {
            try consumer(value)
            super.receive(value)
        }
        catch {
            handle(error)
        }
    }
}

extension Subscription {
    /// Create a downstream subscription that consumes received values
    /// with a given closure.
    ///
    /// - Parameter consumer: A closure that accepts received value
    public func consume(_ consumer: @escaping (Value) throws -> Void) -> Subscription<Value> {
        let subscription = ConsumeSubscription<Value>(publisher: nil, upstream: self, initialValue: initialValue, consumer: consumer)
        downstreams.append(subscription)

        return subscription
    }
}

// MARK: - CaseSubscription

final class CaseSubscription<Value>: Subscription<Value> where Value: Equatable {
    init(publisher: Publisher<Value>?, upstream: Subscription<Value>?, initialValue: Value?, value: Value, handler: @escaping () throws -> Void) {
        self.value = value
        self.handler = handler

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    private var value: Value
    private var handler: () throws -> Void

    override fileprivate func receive(_ value: Value) {
        do {
            if value == self.value {
                try handler()
            }
            super.receive(value)
        }
        catch {
            handle(error)
        }
    }
}

extension Subscription where Value: Equatable {
    /// Creates a downstream subscription that executes given closure
    /// if the received value matches the value of subscription.
    ///
    /// - Parameter value: Value to match
    /// - Parameter handler: Closure that executes if received value matches `value`
    public func `case`(_ value: Value, handler: @escaping () throws -> Void) -> Subscription<Value> {
        let subscription = CaseSubscription<Value>(publisher: publisher, upstream: upstream, initialValue: initialValue, value: value, handler: handler)
        downstreams.append(subscription)

        return subscription
    }
}

// MARK: - ErrorSubscription

final class ErrorSubscription<Value>: Subscription<Value> {
    init(publisher: Publisher<Value>?, upstream: Subscription<Value>?, initialValue: Value?, handler: @escaping (Error) -> Void) {
        self.handler = handler

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    private var handler: (Error) -> Void

    override fileprivate func handle(_ error: Error) {
        handler(error)
        super.handle(error)
    }
}

extension Subscription {
    /// Creates a downstream subscription that executes closure when error is thrown in upstream
    ///
    /// - Parameter handler: Closure to execute in case of an error
    public func `catch`(_ handler: @escaping (Error) -> Void) -> Subscription<Value> {
        let subscription = ErrorSubscription<Value>(publisher: nil, upstream: self, initialValue: initialValue, handler: handler)
        downstreams.append(subscription)

        return subscription
    }
}

// MARK: - FilterSubscription

final class FilterSubscription<Value>: Subscription<Value> {
    init(publisher: Publisher<Value>?, upstream: Subscription<Value>?, initialValue: Value?, predicate: @escaping (Value) throws -> Bool) {
        self.predicate = predicate

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    private var predicate: (Value) throws -> Bool

    override fileprivate func receive(_ value: Value) {
        do {
            guard try predicate(value) else { return }

            super.receive(value)
        }
        catch {
            handle(error)
        }
    }
}

extension Subscription {
    /// Creates a downstream subscription that filters values with a given predicate closure
    ///
    ///
    public func filter(_ predicate: @escaping (Value) throws -> Bool) -> Subscription<Value> {
        let subscription = FilterSubscription<Value>(publisher: nil, upstream: self, initialValue: initialValue, predicate: predicate)
        downstreams.append(subscription)

        return subscription
    }
}

// MARK: - MapSubscription

final class MapSubscription<Input, Output>: Subscription<Input> {
    init(publisher: Publisher<Input>?, upstream: Subscription<Input>?, initialValue: Input?, transform: @escaping (Input) throws -> Output) {
        self.transform = transform

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    fileprivate var transformPublisher = Publisher<Output>()

    private var transform: (Input) throws -> Output

    override fileprivate func receive(_ value: Input) {
        do {
            let transformedValue = try transform(value)

            transformPublisher.publish(transformedValue)
        }
        catch {
            handle(error)
        }
    }
}

extension Subscription {
    public func map<Output>(_ transform: @escaping (Value) throws -> Output) -> Subscription<Output> {
        let transforming = MapSubscription<Value, Output>(publisher: nil, upstream: self, initialValue: initialValue, transform: transform)
        downstreams.append(transforming)

        return transforming.transformPublisher.subscribe()
    }
}

// MARK: - CompactMapSubscription

final class CompactMapSubscription<Input, Output>: Subscription<Input> {
    init(publisher: Publisher<Input>?, upstream: Subscription<Input>?, initialValue: Input?, transform: @escaping (Input) throws -> Output?) {
        self.transform = transform

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    fileprivate var transformPublisher = Publisher<Output>()

    private var transform: (Input) throws -> Output?

    override fileprivate func receive(_ value: Input) {
        do {
            guard let transformedValue = try transform(value) else { return }

            transformPublisher.publish(transformedValue)
        }
        catch {
            handle(error)
        }
    }
}

extension Subscription {
    public func compactMap<Output>(_ transform: @escaping (Value) throws -> Output?) -> Subscription<Output> {
        let transforming = CompactMapSubscription<Value, Output>(publisher: nil, upstream: self, initialValue: initialValue, transform: transform)
        downstreams.append(transforming)

        return transforming.transformPublisher.subscribe()
    }
}

// MARK: - FlatMapSubscription

final class FlatMapSubscription<Input, Output>: Subscription<Input> {
    init(publisher: Publisher<Input>?, upstream: Subscription<Input>?, initialValue: Input?, transform: @escaping (Input) throws -> [Output]) {
        self.transform = transform

        super.init(publisher: publisher, upstream: upstream, initialValue: initialValue)
    }

    fileprivate var transformPublisher = Publisher<Output>()

    private var transform: (Input) throws -> [Output]

    override fileprivate func receive(_ value: Input) {
        do {
            for element in try transform(value) {
                transformPublisher.publish(element)
            }
        }
        catch {
            handle(error)
        }
    }
}

extension Subscription {
    public func flatMap<Output>(_ transform: @escaping (Value) throws -> [Output]) -> Subscription<Output> {
        let transforming = FlatMapSubscription<Value, Output>(publisher: nil, upstream: self, initialValue: initialValue, transform: transform)
        downstreams.append(transforming)

        return transforming.transformPublisher.subscribe()
    }
}
