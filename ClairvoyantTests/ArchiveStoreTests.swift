//
//  ArchiveStoreTests.swift
//  ClairvoyantTests
//
//  Created by Justin Spahr-Summers on 2015-07-11.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Clairvoyant
import XCTest

class ArchiveStoreTests: XCTestCase {
	func testArchiveStore() {
		let temporaryDirectoryURL = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
		let storeURL = temporaryDirectoryURL.URLByAppendingPathComponent(NSUUID().UUIDString).URLByAppendingPathExtension("plist")
		print("Store path: \(storeURL.path!)")

		let name = ArchiveFact(key: "name", value: "Justin Spahr-Summers")
		let email = ArchiveFact(key: "email", value: "justin@jspahrsummers.com")

		do {
			let store: ArchiveStore<String>! = ArchiveStore(storeURL: storeURL)
			XCTAssertNotNil(store)

			var transaction = try store.newTransaction()
			XCTAssertEqual(transaction.openedTimestamp, 0)

			let entity = try transaction.createEntity("jspahrsummers", facts: [ name ])
			XCTAssertEqual(entity.creationTimestamp, transaction.openedTimestamp)
			XCTAssertEqual(Array(entity.facts), [ name ])

			try transaction.assertFacts([ email ], forEntityWithIdentifier: entity.identifier)
			try store.commitTransaction(transaction)
		} catch (let error) {
			XCTFail(String(error))
		}

		do {
			let store: ArchiveStore<String>! = ArchiveStore(storeURL: storeURL)
			XCTAssertNotNil(store)

			var transaction = try store.newTransaction()
			XCTAssertEqual(transaction.openedTimestamp, 1)

			let entity: ArchiveEntity<String>! = transaction["jspahrsummers"]
			XCTAssertTrue(entity != nil)
			XCTAssertEqual(entity.creationTimestamp, 0)
			
			let facts = Set(entity.facts)
			let expectedFacts: Set<ArchiveFact<String>> = [
				name,
				email,
			]

			XCTAssertEqual(facts, expectedFacts)

			XCTAssertEqual(entity["name"]!, name)
			XCTAssertEqual(entity["email"]!, email)
		} catch (let error) {
			XCTFail(String(error))
		}
	}
}
