import XCTest
@testable import PubSub

final class PubSubTests: XCTestCase {
    func testLastValue() {
        let expectation = XCTestExpectation()

        let publisher = Publisher<Int>()
        publisher.publish(10)

        let subscriber = publisher.subscribe(receiveLastValue: true).consume {
            XCTAssertEqual(10, $0)
            expectation.fulfill()
        }
        subscriber.unsubscribe()

        wait(for: [expectation], timeout: 1)
    }

    func testCase() {
        let expectation = XCTestExpectation()

        let publisher = Publisher<Int>()

        let subscription = publisher.subscribe().case(10) {
            XCTFail()
            expectation.fulfill()
        }.case(20) {
            XCTAssertTrue(true)
            expectation.fulfill()
        }

        publisher.publish(20)
        subscription.unsubscribe()

        wait(for: [expectation], timeout: 1)
    }

    func testFilter() {
        let original = [1, 10, 2, 8, 4, 9]

        let publisher = Publisher<Int>()

        var filtered: [Int] = []
        let subscription = publisher.subscribe().filter {
            $0 >= 5
        }.consume {
            filtered.append($0)
        }

        original.forEach(publisher.publish(_:))
        subscription.unsubscribe()

        XCTAssertEqual([10, 8, 9], filtered)
    }

    func testMap() {
        let expectation = XCTestExpectation()

        let publisher = Publisher<Int>()

        let subscriber = publisher.subscribe().map {
            $0 * 2
        }.consume {
            XCTAssertEqual(20, $0)
            expectation.fulfill()
        }

        publisher.publish(10)
        subscriber.unsubscribe()

        wait(for: [expectation], timeout: 1)
    }

    func testCompactMap() {
        let publisher = Publisher<String>()

        let notNilSub = publisher.subscribe(receiveLastValue: false).compactMap {
            Int($0)
        }.consume {
            XCTAssertEqual(10, $0)
        }

        publisher.publish("10")
        notNilSub.unsubscribe()

        let nilSub = publisher.subscribe(receiveLastValue: false).compactMap {
            Int($0)
        }.consume { _ in
            XCTFail()
        }

        publisher.publish("NaN")
        nilSub.unsubscribe()
    }

    func testFlatMap() {
        let original = [1, 5, 10, 3, 7]

        let publisher = Publisher<[Int]>()

        var result: [Int] = []
        let subscriber = publisher.subscribe().flatMap {
            $0
        }.consume {
            result.append($0)
        }

        publisher.publish(original)
        subscriber.unsubscribe()

        XCTAssertEqual(original, result)
    }

    private enum PubSubError: Error {
        case test
    }

    func testError() {
        let expectation = XCTestExpectation()

        let publisher = Publisher<Int>()

        let subscription = publisher.subscribe().consume { _ in
            throw PubSubError.test
        }.catch {
            XCTAssertTrue($0 is PubSubError)
            expectation.fulfill()
        }

        publisher.publish(10)
        subscription.unsubscribe()

        wait(for: [expectation], timeout: 1)
    }

    static var allTests = [
        ("lastValue", testLastValue),
        ("case", testCase),
        ("filter", testFilter),
        ("map", testMap),
        ("compactMap", testCompactMap),
        ("flatMap", testFlatMap),
        ("error", testError)
    ]
}
