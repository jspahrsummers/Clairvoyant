//
//  Data.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-07-11.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

public protocol FactType: Hashable {
	typealias Key: Hashable
	typealias Value: Equatable

	var key: Key { get }
	var value: Value { get }
}

public enum Event<Fact: FactType, Time: Comparable>: Equatable, Comparable {
	case Assertion(Fact, Time)
	case Retraction(Fact, Time)

	var fact: Fact {
		switch self {
		case let .Assertion(fact, _):
			return fact

		case let .Retraction(fact, _):
			return fact
		}
	}

	var timestamp: Time {
		switch self {
		case let .Assertion(_, time):
			return time

		case let .Retraction(_, time):
			return time
		}
	}
}

public func < <Fact, Time>(lhs: Event<Fact, Time>, rhs: Event<Fact, Time>) -> Bool {
	return lhs.timestamp < rhs.timestamp
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

extension Event: Hashable {
	public var hashValue: Int {
		return fact.hashValue
	}
}

public protocol EntityType {
	typealias Identifier: Hashable
	typealias Fact: FactType
	typealias Time: Comparable

	var identifier: Identifier { get }
	var creationTimestamp: Time { get }

	var facts: AnyForwardCollection<Fact> { get }
	func factsAssertedInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Fact>

	var history: AnyForwardCollection<Event<Fact, Time>> { get }
	func historyInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Event<Fact, Time>>

	subscript(key: Fact.Key) -> Fact? { get }
}

extension EntityType {
	internal func factsAssertedInHistory<S: SequenceType where S.Generator.Element == Event<Fact, Time>>(history: S) -> [Fact.Key: Event<Fact, Time>] {
		var facts: [Fact.Key: Event<Fact, Time>] = [:]

		for event in history {
			switch event {
			case let .Assertion(fact, _):
				facts[fact.key] = event

			case let .Retraction(fact, _):
				facts.removeValueForKey(fact.key)
			}
		}

		return facts
	}

	internal func sortedFactsAssertedInHistory<S: SequenceType where S.Generator.Element == Event<Fact, Time>>(history: S) -> [Fact] {
		return factsAssertedInHistory(history).values.sort().map { event in event.fact }
	}
}

public protocol TransactionType {
	typealias Entity: EntityType

	var openedTimestamp: Entity.Time { get }

	var entities: AnyForwardCollection<Entity> { get }
	func entitiesCreatedInTimeInterval(interval: HalfOpenInterval<Entity.Time>) -> AnyForwardCollection<Entity>

	mutating func createEntity(identifier: Entity.Identifier) throws -> Entity
	mutating func assertFact(fact: Entity.Fact, forEntityWithIdentifier: Entity.Identifier) throws
	mutating func retractFact(fact: Entity.Fact, forEntityWithIdentifier: Entity.Identifier) throws

	subscript(identifier: Entity.Identifier) -> Entity? { get }
}

public protocol StoreType {
	typealias Transaction: TransactionType

	func newTransaction() throws -> Transaction

	mutating func commitTransaction(transaction: Transaction) throws
}
