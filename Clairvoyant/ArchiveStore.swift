//
//  ArchiveStore.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-07-25.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

/// Represents anything which can be encoded into an archive.
///
/// This is very much like the built-in <NSCoding> protocol, but is stateless
/// and supports native Swift types.
public protocol Archivable {
	/// Attempts to initialize a value of this type using an object which was
	/// read from an NSCoder.
	init?(coderRepresentation: NSCoding)

	/// Serializes this value into an object that can be written using an
	/// NSCoder.
	var coderRepresentation: NSCoding { get }
}

/// Errors that can occur when using an ArchiveStore or ArchiveTransaction.
public enum ArchiveStoreError<Value: Archivable where Value: Hashable>: ErrorType {
	/// No entity with the specified identifier exists.
	case NoSuchEntity(identifier: ArchiveEntity<Value>.Identifier)

	/// Creating an entity failed because another entity already exists with the
	/// same identifier.
	case EntityAlreadyExists(existingEntity: ArchiveEntity<Value>)

	/// The given fact could not be asserted or retracted because the necessary
	/// preconditions were not met.
	case FactValidationError(fact: ArchiveFact<Value>, onEntity: ArchiveEntity<Value>)

	/// The specified transaction cannot be committed, because another
	/// transaction was successfully committed after the former was opened.
	case TransactionCommitConflict(attemptedTransaction: ArchiveTransaction<Value>)

	/// There was an error unarchiving the store from a file at the given URL.
	case ReadError(storeURL: NSURL)

	/// There was an error archiving the store to a file at the given URL.
	case WriteError(storeURL: NSURL)
}

public struct ArchiveFact<Value: Archivable where Value: Hashable>: FactType {
	public typealias Key = String

	public let key: Key
	public let value: Value

	public init(key: Key, value: Value) {
		self.key = key
		self.value = value
	}

	public var hashValue: Int {
		return key.hashValue ^ value.hashValue
	}
}

public func == <Value>(lhs: ArchiveFact<Value>, rhs: ArchiveFact<Value>) -> Bool {
	return lhs.key == rhs.key && lhs.value == rhs.value
}

extension ArchiveFact: Archivable {
	public init?(coderRepresentation: NSCoding) {
		guard let dictionary = coderRepresentation as? NSDictionary else {
			return nil
		}

		guard let key = dictionary["key"] as? Key else {
			return nil
		}

		guard let archivedValue = dictionary["value"] else {
			return nil
		}

		guard let value = Value(coderRepresentation: archivedValue as! NSCoding) else {
			return nil
		}

		self.init(key: key, value: value)
	}

	public var coderRepresentation: NSCoding {
		return [
			"key": self.key,
			"value": self.value.coderRepresentation
		]
	}
}

extension String: Archivable {
	public init?(coderRepresentation: NSCoding) {
		guard let string = coderRepresentation as? String else {
			return nil
		}

		self.init(string)
	}

	public var coderRepresentation: NSCoding {
		return self
	}
}

extension UInt: Archivable {
	public init?(coderRepresentation: NSCoding) {
		guard let number = coderRepresentation as? NSNumber else {
			return nil
		}

		self.init(number)
	}

	public var coderRepresentation: NSCoding {
		return self
	}
}

/// Attempts to unarchive an Event from the given object.
private func eventWithCoderRepresentation<Value: Archivable>(coderRepresentation: NSCoding) -> Event<ArchiveFact<Value>, ArchiveEntity<Value>.Time>? {
	guard let dictionary = coderRepresentation as? NSDictionary else {
		return nil
	}

	guard let type = dictionary["type"] as? String else {
		return nil
	}

	guard let archivedFact = dictionary["fact"] else {
		return nil
	}

	guard let fact = ArchiveFact<Value>(coderRepresentation: archivedFact as! NSCoding) else {
		return nil
	}

	guard let archivedTime = dictionary["time"] else {
		return nil
	}

	guard let time = ArchiveEntity<Value>.Time(coderRepresentation: archivedTime as! NSCoding) else {
		return nil
	}

	switch type {
	case "assertion":
		return .Assertion(fact, time)

	case "retraction":
		return .Retraction(fact, time)

	default:
		return nil
	}
}

/// Archives an event into an object that can be encoded.
private func coderRepresentationOfEvent<Value: Archivable>(event: Event<ArchiveFact<Value>, ArchiveEntity<Value>.Time>) -> NSCoding {
	let type: String

	switch event {
	case .Assertion:
		type = "assertion"

	case .Retraction:
		type = "retraction"
	}

	return [
		"type": type,
		"fact": event.fact.coderRepresentation,
		"time": event.timestamp.coderRepresentation
	]
}

public struct ArchiveEntity<Value: Archivable where Value: Hashable>: EntityType {
	public typealias Identifier = String
	public typealias Fact = ArchiveFact<Value>
	public typealias Time = UInt

	private var events: [Event<Fact, Time>]

	public let identifier: Identifier
	public let creationTimestamp: Time

	private init(identifier: Identifier, creationTimestamp: Time) {
		self.identifier = identifier
		self.creationTimestamp = creationTimestamp

		events = []
	}

	public var history: AnyForwardCollection<Event<Fact, Time>> {
		return AnyForwardCollection(events)
	}
}

extension ArchiveEntity: Archivable {
	public init?(coderRepresentation: NSCoding) {
		guard let dictionary = coderRepresentation as? NSDictionary else {
			return nil
		}

		guard let identifier = dictionary["identifier"] as? String else {
			return nil
		}

		guard let archivedTime = dictionary["time"] else {
			return nil
		}

		guard let time = Time(coderRepresentation: archivedTime as! NSCoding) else {
			return nil
		}

		guard let archivedEvents = dictionary["events"] as? NSArray else {
			return nil
		}

		self.identifier = identifier
		self.creationTimestamp = time

		events = []

		for archivedEvent in archivedEvents {
			guard let event: Event<Fact, Time> = eventWithCoderRepresentation(archivedEvent as! NSCoding) else {
				return nil
			}

			events.append(event)
		}
	}

	public var coderRepresentation: NSCoding {
		let archivedEvents = events.map(coderRepresentationOfEvent) as NSArray

		return [
			"identifier": identifier,
			"events": archivedEvents,
			"time": creationTimestamp.coderRepresentation,
		]
	}
}

public struct ArchiveTransaction<Value: Archivable where Value: Hashable>: TransactionType {
	public typealias Entity = ArchiveEntity<Value>

	private var entitiesByIdentifier: [Entity.Identifier: Entity]

	public let openedTimestamp: Entity.Time

	private init?(openedTimestamp: Entity.Time, archivedEntities: NSArray) {
		self.openedTimestamp = openedTimestamp

		entitiesByIdentifier = [:]
		for archivedEntity in archivedEntities {
			guard let entity = Entity(coderRepresentation: archivedEntity as! NSCoding) else {
				return nil
			}

			entitiesByIdentifier[entity.identifier] = entity
		}
	}

	public var entities: AnyForwardCollection<Entity> {
		return AnyForwardCollection(entitiesByIdentifier.values)
	}

	public mutating func createEntity(identifier: Entity.Identifier, facts: [Entity.Fact]) throws -> Entity {
		if let existingEntity = entitiesByIdentifier[identifier] {
			throw ArchiveStoreError<Value>.EntityAlreadyExists(existingEntity: existingEntity)
		}

		var entity = Entity(identifier: identifier, creationTimestamp: openedTimestamp)
		try assertFacts(facts, forEntity: &entity)

		return entity
	}

	public mutating func assertFacts(facts: [Entity.Fact], forEntityWithIdentifier identifier: Entity.Identifier) throws {
		guard var entity = entitiesByIdentifier[identifier] else {
			throw ArchiveStoreError<Value>.NoSuchEntity(identifier: identifier)
		}

		try assertFacts(facts, forEntity: &entity)
	}

	private mutating func assertFacts(facts: [Entity.Fact], inout forEntity entity: Entity) throws {
		for fact in facts {
			guard !entity.facts.contains(fact) else {
				throw ArchiveStoreError<Value>.FactValidationError(fact: fact, onEntity: entity)
			}

			entity.events.append(.Assertion(fact, openedTimestamp))
		}

		entitiesByIdentifier[entity.identifier] = entity
	}

	public mutating func retractFacts(facts: [Entity.Fact], forEntityWithIdentifier identifier: Entity.Identifier) throws {
		guard var entity = entitiesByIdentifier[identifier] else {
			throw ArchiveStoreError<Value>.NoSuchEntity(identifier: identifier)
		}

		for fact in facts {
			guard entity.facts.contains(fact) else {
				throw ArchiveStoreError<Value>.FactValidationError(fact: fact, onEntity: entity)
			}

			entity.events.append(.Retraction(fact, openedTimestamp))
		}

		entitiesByIdentifier[identifier] = entity
	}

	public subscript(identifier: Entity.Identifier) -> Entity? {
		return entitiesByIdentifier[identifier]
	}
}

/// A database store backed by NSKeyedArchiver, and written into a property list
/// on disk.
///
/// `ArchiveStore`s do not support conflict resolution. Any transaction making
/// changes should be committed before opening another transaction to make
/// changes, or else a conflict could result in the second transaction being
/// rejected at commit time. Any number of read-only transactions can be open
/// while making changes, without issue.
public final class ArchiveStore<Value: Archivable where Value: Hashable>: StoreType {
	public typealias Transaction = ArchiveTransaction<Value>

	public let storeURL: NSURL

	private var transactionTimestamp: Transaction.Entity.Time
	private var archivedEntities: NSArray

	/// Opens a database store that will read from and write to a property list
	/// at the given file URL.
	///
	/// If the file does not exist yet, it will be created the first time
	/// a transaction is committed.
	public init?(storeURL: NSURL) {
		precondition(storeURL.fileURL)

		self.storeURL = storeURL

		guard let unarchivedObject = NSKeyedUnarchiver.unarchiveObjectWithFile(storeURL.path!) else {
			archivedEntities = []
			transactionTimestamp = 0
			return
		}

		guard
			let dictionary = unarchivedObject as? NSDictionary,
			let entities = dictionary["entities"] as? NSArray,
			let archivedTimestamp = dictionary["timestamp"],
			let timestamp = Transaction.Entity.Time(coderRepresentation: archivedTimestamp as! NSCoding)
		else {
			archivedEntities = []
			transactionTimestamp = 0
			return nil
		}

		archivedEntities = entities
		transactionTimestamp = timestamp
	}

	public func newTransaction() throws -> Transaction {
		guard let transaction = Transaction(openedTimestamp: transactionTimestamp, archivedEntities: archivedEntities) else {
			throw ArchiveStoreError<Value>.ReadError(storeURL: storeURL)
		}

		return transaction
	}

	public func commitTransaction(transaction: Transaction) throws {
		guard transaction.openedTimestamp == transactionTimestamp else {
			throw ArchiveStoreError<Value>.TransactionCommitConflict(attemptedTransaction: transaction)
		}

		transactionTimestamp++
		archivedEntities = transaction.entities.map { $0.coderRepresentation }

		let dictionary: NSDictionary = [
			"entities": archivedEntities,
			"timestamp": transactionTimestamp.coderRepresentation,
		]

		if !NSKeyedArchiver.archiveRootObject(dictionary, toFile: storeURL.path!) {
			throw ArchiveStoreError<Value>.WriteError(storeURL: storeURL)
		}
	}
}
