//
//  KeyedArchiveTests.swift
//  KeyedArchiveTests
//
//  Created by Justin Spahr-Summers on 2015-07-11.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Clairvoyant
import XCTest

class KeyedArchiveTests: XCTestCase {
	func testArchiveStore() {
		let temporaryDirectoryURL = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
		let storeURL = temporaryDirectoryURL.URLByAppendingPathComponent(NSUUID().UUIDString).URLByAppendingPathExtension("plist")
		print("Store path: \(storeURL.path!)")

		let nameFact = ArchiveFact(key: "name", value: "Justin Spahr-Summers")
		let emailFact = ArchiveFact(key: "email", value: "justin@jspahrsummers.com")

		do {
			let store: ArchiveStore<String>! = ArchiveStore(storeURL: storeURL)
			XCTAssertNotNil(store)

			var transaction = try store.newTransaction()
			XCTAssertEqual(transaction.openedTimestamp, 0)

			let entity = try transaction.createEntity("jspahrsummers")
			XCTAssertEqual(entity.creationTimestamp, transaction.openedTimestamp)

			try transaction.assertFact(nameFact, forEntityWithIdentifier: entity.identifier)
			try transaction.assertFact(emailFact, forEntityWithIdentifier: entity.identifier)

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
				nameFact,
				emailFact,
			]

			XCTAssertEqual(facts, expectedFacts)
		} catch (let error) {
			XCTFail(String(error))
		}
	}
}
