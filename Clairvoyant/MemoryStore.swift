//
//  MemoryStore.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-08-15.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

/// Errors that can occur when using a MemoryStore or MemoryTransaction.
public enum MemoryStoreError<Identifier: Hashable, Time: Comparable, Fact: FactType>: ErrorType {
	/// No entity with the specified identifier exists.
	case NoSuchEntity(identifier: Identifier)

	/// Creating an entity failed because another entity already exists with the
	/// same identifier.
	case EntityAlreadyExists(existingEntity: MemoryEntity<Identifier, Time, Fact>)

	/// The given fact could not be asserted or retracted because the necessary
	/// preconditions were not met.
	case FactValidationError(fact: Fact, onEntity: MemoryEntity<Identifier, Time, Fact>)

	/// The specified transaction cannot be committed, because another
	/// transaction was successfully committed after the former was opened.
	case TransactionCommitConflict(attemptedTransaction: MemoryTransaction<Identifier, Time, Fact>)
}

/// A simple, in-memory fact.
///
/// Although designed for use with MemoryEntity, there is no requirement to use
/// the MemoryFact type. You can instead use any FactType, which is especially
/// convenient for testing.
public struct MemoryFact<Key: Hashable, Value: Equatable>: FactType {
	public let key: Key
	public let value: Value

	public init(key: Key, value: Value) {
		self.key = key
		self.value = value
	}

	public var hashValue: Int {
		return key.hashValue
	}
}

public func == <Key, Value>(lhs: MemoryFact<Key, Value>, rhs: MemoryFact<Key, Value>) -> Bool {
	return lhs.key == rhs.key && lhs.value == rhs.value
}

public struct MemoryEntity<Identifier: Hashable, Time: Comparable, Fact: FactType>: EntityType {
	public let identifier: Identifier
	public let creationTimestamp: Time

	private var events: [Event<Fact, Time>]

	public init(identifier: Identifier, creationTimestamp: Time, events: [Event<Fact, Time>]) {
		self.identifier = identifier
		self.creationTimestamp = creationTimestamp
		self.events = events
	}

	public var history: AnyForwardCollection<Event<Fact, Time>> {
		return AnyForwardCollection(events)
	}
}

// TODO: Reuse implementation with ArchiveTransaction?
public struct MemoryTransaction<Identifier: Hashable, Time: Comparable, Fact: FactType>: TransactionType {
	public typealias Entity = MemoryEntity<Identifier, Time, Fact>

	public let openedTimestamp: Time

	private var entitiesByIdentifier: [Identifier: Entity]

	private init(openedTimestamp: Time, entitiesByIdentifier: [Identifier: Entity]) {
		self.openedTimestamp = openedTimestamp
		self.entitiesByIdentifier = entitiesByIdentifier
	}

	public var entities: AnyForwardCollection<Entity> {
		return AnyForwardCollection(entitiesByIdentifier.values)
	}

	public mutating func createEntity(identifier: Entity.Identifier, facts: [Entity.Fact]) throws -> Entity {
		if let existingEntity = entitiesByIdentifier[identifier] {
			throw MemoryStoreError<Identifier, Time, Fact>.EntityAlreadyExists(existingEntity: existingEntity)
		}

		var entity = Entity(identifier: identifier, creationTimestamp: openedTimestamp, events: [])
		try assertFacts(facts, forEntity: &entity)

		return entity
	}

	public mutating func assertFacts(facts: [Entity.Fact], forEntityWithIdentifier identifier: Entity.Identifier) throws {
		guard var entity = entitiesByIdentifier[identifier] else {
			throw MemoryStoreError<Identifier, Time, Fact>.NoSuchEntity(identifier: identifier)
		}

		try assertFacts(facts, forEntity: &entity)
	}

	private mutating func assertFacts(facts: [Entity.Fact], inout forEntity entity: Entity) throws {
		for fact in facts {
			guard !entity.facts.contains(fact) else {
				throw MemoryStoreError<Identifier, Time, Fact>.FactValidationError(fact: fact, onEntity: entity)
			}

			entity.events.append(.Assertion(fact, openedTimestamp))
		}

		entitiesByIdentifier[entity.identifier] = entity
	}

	public mutating func retractFacts(facts: [Entity.Fact], forEntityWithIdentifier identifier: Entity.Identifier) throws {
		guard var entity = entitiesByIdentifier[identifier] else {
			throw MemoryStoreError<Identifier, Time, Fact>.NoSuchEntity(identifier: identifier)
		}

		for fact in facts {
			guard entity.facts.contains(fact) else {
				throw MemoryStoreError<Identifier, Time, Fact>.FactValidationError(fact: fact, onEntity: entity)
			}

			entity.events.append(.Retraction(fact, openedTimestamp))
		}

		entitiesByIdentifier[identifier] = entity
	}

	public subscript(identifier: Entity.Identifier) -> Entity? {
		return entitiesByIdentifier[identifier]
	}
}

/// A database stored entirely in memory, useful for data that does not need to
/// persisted, or for automated testing.
///
/// For maximum flexibility, especially in testing, almost all of the concrete
/// types used by a MemoryStore can be customized.
///
/// MemoryStore is a value type. As such, instances of it can be copied and
/// manipulated independently, without affecting each other.
///
/// MemoryStores do not support conflict resolution. Any transaction making
/// changes should be committed before opening another transaction to make
/// changes, or else a conflict could result in the second transaction being
/// rejected at commit time. Any number of read-only transactions can be open
/// while making changes, without issue.
public struct MemoryStore<Identifier: Hashable, Time: Comparable, Fact: FactType where Time: ForwardIndexType>: StoreType {
	public typealias Transaction = MemoryTransaction<Identifier, Time, Fact>

	private var transactionTimestamp: Time
	private var entitiesByIdentifier: [Identifier: Transaction.Entity]

	/// Instantiates a new in-memory store, which will begin at the given
	/// timestamp and have the given entities.
	///
	/// Every successful invocation of commitTransaction() will increment the
	/// timestamp by 1.
	public init(initialTimestamp: Time, entities: [Transaction.Entity] = []) {
		transactionTimestamp = initialTimestamp

		entitiesByIdentifier = [:]
		for entity in entities {
			entitiesByIdentifier[entity.identifier] = entity
		}
	}

	public func newTransaction() throws -> Transaction {
		return Transaction(openedTimestamp: transactionTimestamp, entitiesByIdentifier: entitiesByIdentifier)
	}

	public mutating func commitTransaction(transaction: Transaction) throws {
		guard transaction.openedTimestamp == transactionTimestamp else {
			throw MemoryStoreError<Identifier, Time, Fact>.TransactionCommitConflict(attemptedTransaction: transaction)
		}

		entitiesByIdentifier = transaction.entitiesByIdentifier
		transactionTimestamp++
	}
}
