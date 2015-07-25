//
//  Data.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-07-11.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

public protocol FactType: Equatable {
	typealias Key: Hashable
	typealias Value: Equatable

	var key: Key { get }
	var value: Value { get }
}

public protocol TimeType: Comparable {
}

public enum Event<Fact: FactType, Time: TimeType>: Equatable {
	case Assertion(Fact, Time)
	case Retraction(Fact, Time)

	var timestamp: Time {
		switch self {
		case let .Assertion(_, time):
			return time

		case let .Retraction(_, time):
			return time
		}
	}
}

public func == <Fact, Time>(lhs: Event<Fact, Time>, rhs: Event<Fact, Time>) -> Bool {
	switch (lhs, rhs) {
	case let (.Assertion(leftFact, leftTime), .Assertion(rightFact, rightTime)):
		return leftFact == rightFact && leftTime == rightTime
	
	case let (.Retraction(leftFact, leftTime), .Retraction(rightFact, rightTime)):
		return leftFact == rightFact && leftTime == rightTime
	
	default:
		return false
	}
}

public protocol EntityType: Equatable {
	typealias Identifier: Hashable
	typealias Fact: FactType
	typealias Time: TimeType

	var facts: AnyForwardCollection<Fact> { get }
	func factsAssertedInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Fact>

	var history: AnyForwardCollection<Event<Fact, Time>> { get }
	func historyInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Event<Fact, Time>>

	subscript(key: Fact.Key) -> Fact? { get }
}

public protocol TransactionType {
	typealias Entity: EntityType

	var timestamp: Entity.Time { get }

	var entities: AnyForwardCollection<Entity> { get }
	func entitiesCreatedInTimeInterval(interval: HalfOpenInterval<Entity.Time>) -> AnyForwardCollection<Entity>

	mutating func createEntity(identifier: Entity.Identifier) throws -> Entity
	mutating func assertFact(fact: Entity.Fact, forEntityWithIdentifier: Entity.Identifier) throws
	mutating func retractFact(fact: Entity.Fact, forEntityWithIdentifier: Entity.Identifier) throws

	subscript(identifier: Entity.Identifier) -> Entity? { get }
}

public protocol StoreType {
	typealias Transaction: TransactionType

	func openTransaction() -> Transaction

	mutating func saveTransaction(transaction: Transaction) throws
}
