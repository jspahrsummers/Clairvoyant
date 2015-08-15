//
//  Data.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-07-11.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

/// Represents a "fact," which is (in its most basic form) a key-value statement
/// about a database entity.
///
/// Facts may be "asserted," which adds them to an entity. Once asserted, facts
/// may not be modified—they can only be "retracted" to nullify them, and the
/// history of assertions and retractions stays forever with the entity.
///
/// The facts of any particular concrete database implementation may carry more
/// information than required by this protocol.
public protocol FactType: Hashable {
	/// The type of key used to identify facts of this type.
	typealias Key: Hashable

	/// The type of value associated with facts of this type.
	typealias Value: Equatable

	/// The unique key for this fact.
	///
	/// An entity may only have one value per key in its list of asserted facts.
	/// For an existing key to be reused, the original fact must first be
	/// retracted.
	var key: Key { get }

	/// The value associated with the key.
	var value: Value { get }
}

/// An event about a fact that occurred at a certain point in time.
///
/// Time, here, does not necessarily represent wallclock time. It can be any
/// type of increasing value preferred by the concrete database implementation.
public enum Event<Fact: FactType, Time: Comparable>: Equatable, Comparable {
	/// The fact was asserted at the specified time.
	case Assertion(Fact, Time)

	/// The fact was retracted at the specified time.
	case Retraction(Fact, Time)

	/// The fact associated with this event.
	var fact: Fact {
		switch self {
		case let .Assertion(fact, _):
			return fact

		case let .Retraction(fact, _):
			return fact
		}
	}

	/// The database timestamp at which this event occurred.
	///
	/// Multiple events may have the same `timestamp`.
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

/// An immutable view of a database entity as seen at a specific point in time.
///
/// All concrete implementations of EntityType are thread-safe.
public protocol EntityType {
	/// The type of unique identifier used for entities of this type.
	typealias Identifier: Hashable

	/// The type of facts associated with entities of this type.
	typealias Fact: FactType

	/// The type of a "timestamp" in this concrete database implementation,
	/// which may not necessarily represent wallclock time.
	typealias Time: Comparable

	/// The unique identifier for this entity in the database.
	///
	/// Attempting to create two entities with the same identifier will generate
	/// an error.
	var identifier: Identifier { get }

	/// The database timestamp at which this entity was created.
	///
	/// Multiple entities may have the same `creationTimestamp`.
	var creationTimestamp: Time { get }

	/// A list of all events that have occurred to this entity, in ascending
	/// timestamp order.
	var history: AnyForwardCollection<Event<Fact, Time>> { get }
}

extension EntityType {
	/// A list of all events that occurred to this entity within the given time
	/// interval, in ascending order.
	public func historyInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Event<Fact, Time>> {
		let filteredEvents = history.filter { interval.contains($0.timestamp) }
		return AnyForwardCollection(filteredEvents)
	}

	/// A list of all "current" facts that have been asserted about this entity
	/// and not yet retracted, in ascending timestamp order.
	public var facts: AnyForwardCollection<Fact> {
		return AnyForwardCollection(sortedFactsAssertedInHistory(history))
	}

	/// Returns all "current" facts that were asserted about this entity within
	/// the given time interval, and that have not yet been retracted, in
	/// ascending timestamp order.
	public func factsAssertedInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Fact> {
		let filteredHistory = historyInTimeInterval(interval)
		return AnyForwardCollection(sortedFactsAssertedInHistory(filteredHistory))
	}

	/// Looks up the given key within this entity's `facts`, returning any fact
	/// with a matching key that has been asserted and not yet retracted.
	public subscript(key: Fact.Key) -> Fact? {
		return factsByKeyAssertedInHistory(history)[key].map { event in event.fact }
	}
}

/// Returns the keys of all facts that were asserted (and not retracted) in the
/// given event history, associating each key with the asserting event itself.
///
/// This is mostly useful inside concrete implementations of EntityType.
public func factsByKeyAssertedInHistory<Fact: FactType, Time, S: SequenceType where S.Generator.Element == Event<Fact, Time>>(history: S) -> [Fact.Key: Event<Fact, Time>] {
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

/// Returns a list of all facts that were asserted (and not retracted) in the
/// given event history, sorted in ascending timestamp order.
///
/// This is mostly useful inside concrete implementations of EntityType.
public func sortedFactsAssertedInHistory<Fact: FactType, Time: Comparable, S: SequenceType where S.Generator.Element == Event<Fact, Time>>(history: S) -> [Fact] {
	return factsByKeyAssertedInHistory(history).values.sort().map { event in event.fact }
}

/// Represents a transaction, which behaves like a log of changes to be made to
/// the database.
///
/// A transaction's view of the underlying database never changes. All entities
/// read from the transaction will appear as they were at the time that the
/// transaction was opened, except for changes that have been made through that
/// specific transaction itself. In other words, changes made through any given
/// transaction will not be visible to all other transactions open at the same
/// time.
///
/// Changes made through a transaction have no effect on the underlying database
/// until committed. Transactions do not necessarily need to be committed—they
/// can be used as a "scratch pad" for changes, and then those changes can be
/// thrown away (by releasing the transaction) instead of being saved to the
/// database.
///
/// The thread-safety of a TransactionType depends on the specific
/// implementation. For maximum compatibility, perform all operations on
/// a transaction from a single thread. However, separate transactions can
/// always be used concurrently on separate threads.
public protocol TransactionType {
	/// The type of entity accessible through a transaction of this type.
	typealias Entity: EntityType

	/// The database timestamp at which the transaction was opened.
	var openedTimestamp: Entity.Time { get }

	/// A list of all entities in the database, as seen by this transaction. The
	/// ordering is implementation-defined.
	///
	/// The entities returned in this way will include any changes made inside
	/// this transaction, but will not include changes made by other
	/// transactions since this one was opened.
	var entities: AnyForwardCollection<Entity> { get }

	/// Creates a new entity, having the given unique identifier, and asserts
	/// the given list of facts about it immediately.
	///
	/// Returns an immutable copy of the entity that was created. Further
	/// changes to the entity via `assertFacts` or `retractFacts` will not be
	/// reflected in the value returned from this method.
	///
	/// Throws an error if an entity already exists with the given identifier.
	mutating func createEntity(identifier: Entity.Identifier, facts: [Entity.Fact]) throws -> Entity

	/// Asserts the given list of facts about the entity having the given
	/// identifier, in addition to whatever facts have already been asserted
	/// about it.
	///
	/// Throws an error if an entity does not exist with the given identifier,
	/// or if any of the asserted facts' keys already have an associated value
	/// for the entity.
	mutating func assertFacts(facts: [Entity.Fact], forEntityWithIdentifier: Entity.Identifier) throws

	/// Retracts the given list of facts about the entity having the given
	/// identifier, so that they will no longer be considered "current" or
	/// listed in the entity's `facts`.
	///
	/// After this method finishes, new facts may be asserted that reuse the
	/// keys of the retracted facts.
	///
	/// Throws an error if an entity does not exist with the given identifier,
	/// or if any of the given facts have not been asserted or were already
	/// retracted.
	mutating func retractFacts(facts: [Entity.Fact], forEntityWithIdentifier: Entity.Identifier) throws

	/// Attempts to find an entity having the given identifier.
	subscript(identifier: Entity.Identifier) -> Entity? { get }
}

extension TransactionType {
	/// Returns a list of entities that were created within the given time
	/// interval, in ascending order of `creationTimestamp`.
	///
	/// The entities returned in this way will include any changes made inside
	/// this transaction, but will not include changes made by other
	/// transactions since this one was opened.
	public func entitiesCreatedInTimeInterval(interval: HalfOpenInterval<Entity.Time>) -> AnyForwardCollection<Entity> {
		let filteredEntities = entities.filter { interval.contains($0.creationTimestamp) }
		return AnyForwardCollection(filteredEntities)
	}
}

/// Represents a concrete database store.
///
/// The thread-safety of a StoreType depends on the specific implementation. For
/// maximum compatibility, perform all invocations of newTransaction() and
/// commitTransaction() on a single thread.
public protocol StoreType {
	/// The type of transaction used for this database store.
	typealias Transaction: TransactionType

	/// Opens a new transaction, having the complete current state of the
	/// database.
	///
	/// The errors that may be thrown here are determined by the specific
	/// concrete implementation.
	func newTransaction() throws -> Transaction

	/// Attempts to commit the changes of the given transaction to the database
	/// store.
	///
	/// It is implementation-defined what happens when this method is invoked
	/// multiple times with the same transaction.
	///
	/// The errors that may be thrown here are determined by the specific
	/// concrete implementation.
	mutating func commitTransaction(transaction: Transaction) throws
}
