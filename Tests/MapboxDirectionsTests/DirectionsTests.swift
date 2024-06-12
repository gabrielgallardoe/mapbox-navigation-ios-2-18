import XCTest
#if !os(Linux)
import OHHTTPStubs
#if SWIFT_PACKAGE
import OHHTTPStubsSwift
#endif
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
@testable import MapboxDirections
import Turf

let BogusToken = "pk.feedCafeDadeDeadBeef-BadeBede.FadeCafeDadeDeed-BadeBede"
let BogusCredentials = Credentials(accessToken: BogusToken)
let BadResponse = """
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<HTML><HEAD><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=iso-8859-1">
<TITLE>ERROR: The request could not be satisfied</TITLE>
</HEAD><BODY>
<H1>413 ERROR</H1>
<H2>The request could not be satisfied.</H2>
<HR noshade size="1px">
Bad request.

<BR clear="all">
<HR noshade size="1px">
<PRE>
Generated by cloudfront (CloudFront)
Request ID: RAf2XH13mMVxQ96Z1cVQMPrd-hJoVA6LfaWVFDbdN2j-J1VkzaPvZg==
</PRE>
<ADDRESS>
</ADDRESS>
</BODY></HTML>
"""

#if !os(Linux)
class DirectionsTests: XCTestCase {
    private let skuToken: String = "1234567890"

    override func setUp() {
        // Make sure tests run in all time zones
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        MBXAccounts.serviceSkuToken = skuToken
        MBXAccounts.serviceAccessToken = BogusCredentials.accessToken
    }

    override func tearDown() {
        HTTPStubs.removeAllStubs()
        super.tearDown()
        MBXAccounts.serviceSkuToken = nil
    }

    func testConfiguration() {
        let directions = Directions(credentials: BogusCredentials)
        XCTAssertEqual(directions.credentials, BogusCredentials)
    }

    func testUrlForCalculationCredentials() {
        let coordinates = [
            LocationCoordinate2D(latitude: 1, longitude: 2),
            LocationCoordinate2D(latitude: 3, longitude: 4),
        ]
        let options = RouteOptions(coordinates: coordinates)
        let url = Directions.url(forCalculating: options, credentials: BogusCredentials)
        guard let components = URLComponents(string: url.absoluteString),
              let queryItems = components.queryItems
        else {
            XCTFail("Invalid url"); return
        }
        XCTAssertTrue(queryItems.contains(where: { $0.name == "access_token" && $0.value == BogusToken }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "sku" && $0.value == BogusCredentials.skuToken }))
    }

    let maximumCoordinateCount = 10000

    // TODO: Restore test, something isn't right in max calculation
    func disabled_testGETRequest() {
        // Bumps right up against MaximumURLLength
        let coordinates = Array(
            repeating: LocationCoordinate2D(latitude: 0, longitude: 0),
            count: maximumCoordinateCount
        )
        let options = RouteOptions(coordinates: coordinates)

        let directions = Directions(credentials: BogusCredentials)
        let url = directions.url(forCalculating: options, httpMethod: "GET")
        XCTAssertLessThanOrEqual(url.absoluteString.count, MaximumURLLength, "maximumCoordinateCount is too high")

        guard let components = URLComponents(string: url.absoluteString),
              let queryItems = components.queryItems
        else {
            XCTFail("Invalid url"); return
        }
        XCTAssertEqual(queryItems.count, 8)
        let expectedComponent = coordinates.map(\.requestDescription).joined(separator: ";")
        XCTAssertTrue(components.path.contains(expectedComponent))
        XCTAssert(queryItems.contains(where: { $0.name == "sku" && $0.value == skuToken }) == true)
        XCTAssert(queryItems.contains(where: { $0.name == "access_token" && $0.value == BogusToken }) == true)

        let request = directions.urlRequest(forCalculating: options)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, url)
    }

    func testPOSTRequest() {
        let coordinates = Array(
            repeating: LocationCoordinate2D(latitude: 0, longitude: 0),
            count: maximumCoordinateCount + 1
        )
        let options = RouteOptions(coordinates: coordinates)
        options.alleyPriority = .medium

        let directions = Directions(credentials: BogusCredentials)
        let request = directions.urlRequest(forCalculating: options)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.query, "access_token=\(BogusToken)&sku=\(skuToken)")
        XCTAssertNotNil(request.httpBody)
        var components = URLComponents()
        components.query = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(components.queryItems?.count, 8)
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "coordinates" }?.value,
            coordinates.map(\.requestDescription).joined(separator: ";")
        )
    }

    func testKnownBadResponse() {
        HTTPStubs.stubRequests(passingTest: { request -> Bool in
            return request.url!.absoluteString.contains("https://api.mapbox.com/directions")
        }) { _ -> HTTPStubsResponse in
            return HTTPStubsResponse(
                data: BadResponse.data(using: .utf8)!,
                statusCode: 413,
                headers: ["Content-Type": "text/html"]
            )
        }
        let expectation = expectation(description: "Async callback")
        let one = CLLocation(latitude: 0.0, longitude: 0.0)
        let two = CLLocation(latitude: 2.0, longitude: 2.0)

        let directions = Directions(credentials: BogusCredentials)
        let opts = RouteOptions(locations: [one, two])
        directions.calculate(opts, completionHandler: { result in

            guard case .failure(let error) = result else {
                XCTFail("Expecting error, none returned.")
                return
            }

            XCTAssertEqual(error, .requestTooLarge)
            expectation.fulfill()
        })
        wait(for: [expectation], timeout: 2.0)
    }

    func testUnknownBadResponse() {
        let message = "Enhance your calm, John Spartan."
        HTTPStubs.stubRequests(passingTest: { request -> Bool in
            return request.url!.absoluteString.contains("https://api.mapbox.com/directions")
        }) { _ -> HTTPStubsResponse in
            return HTTPStubsResponse(
                data: message.data(using: .utf8)!,
                statusCode: 420,
                headers: ["Content-Type": "text/plain"]
            )
        }
        let expectation = expectation(description: "Async callback")
        let one = CLLocation(latitude: 0.0, longitude: 0.0)
        let two = CLLocation(latitude: 2.0, longitude: 2.0)

        let directions = Directions(credentials: BogusCredentials)
        let opts = RouteOptions(locations: [one, two])
        directions.calculate(opts, completionHandler: { result in
            defer { expectation.fulfill() }

            guard case .failure(let error) = result else {
                XCTFail("Expecting an error, none returned. \(result)")
                return
            }

            guard case .invalidResponse = error else {
                XCTFail("Wrong error type returned.")
                return
            }

        })
        wait(for: [expectation], timeout: 2.0)
    }

    func testRateLimitErrorParsing() {
        let url = URL(string: "https://api.mapbox.com")!
        let headerFields = [
            "X-Rate-Limit-Interval": "60",
            "X-Rate-Limit-Limit": "600",
            "X-Rate-Limit-Reset": "1479460584",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headerFields)

        let resultError = DirectionsError(
            code: "429",
            message: "Hit rate limit",
            response: response,
            underlyingError: nil
        )
        if case .rateLimited(let rateLimitInterval, let rateLimit, let resetTime) = resultError {
            XCTAssertEqual(rateLimitInterval, 60.0)
            XCTAssertEqual(rateLimit, 600)
            XCTAssertEqual(resetTime, Date(timeIntervalSince1970: 1479460584))
        } else {
            XCTFail("Code 429 should be interpreted as a rate limiting error.")
        }
    }

    func testDownNetwork() {
        let notConnected = NSError(
            domain: NSURLErrorDomain,
            code: URLError.notConnectedToInternet.rawValue
        ) as! URLError

        HTTPStubs.stubRequests(passingTest: { request -> Bool in
            return request.url!.absoluteString.contains("https://api.mapbox.com/directions")
        }) { _ -> HTTPStubsResponse in
            return HTTPStubsResponse(error: notConnected)
        }

        let expectation = expectation(description: "Async callback")
        let one = CLLocation(latitude: 0.0, longitude: 0.0)
        let two = CLLocation(latitude: 2.0, longitude: 2.0)

        let directions = Directions(credentials: BogusCredentials)
        let opts = RouteOptions(locations: [one, two])
        directions.calculate(opts, completionHandler: { result in
            defer { expectation.fulfill() }

            guard case .failure(let error) = result else {
                XCTFail("Error expected, none returned. \(result)")
                return
            }

            guard case .network(let err) = error else {
                XCTFail("Wrong error type returned. \(error)")
                return
            }

            // Comparing just the code and domain to avoid comparing unessential `UserInfo` that might be added.
            XCTAssertEqual(type(of: err).errorDomain, type(of: notConnected).errorDomain)
            XCTAssertEqual(err.code, notConnected.code)
        })
        wait(for: [expectation], timeout: 2.0)
    }

    func testRefreshRouteRequest() {
        let directions = Directions(credentials: BogusCredentials)
        guard let url = directions.urlRequest(forRefreshing: "any", routeIndex: 0, fromLegAtIndex: 0).url else {
            XCTFail("Incorrect request"); return
        }
        XCTAssertLessThanOrEqual(url.absoluteString.count, MaximumURLLength, "maximumCoordinateCount is too high")

        guard let queryItems = URLComponents(string: url.absoluteString)?.queryItems else {
            XCTFail("Invalid url"); return
        }
        XCTAssertEqual(queryItems.count, 2)
        XCTAssertTrue(queryItems.contains(where: { $0.name == "sku" && $0.value == skuToken }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "access_token" && $0.value == BogusToken }))
    }
}
#endif
