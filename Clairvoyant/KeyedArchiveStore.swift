//
//  KeyedArchiveStore.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-07-25.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

public protocol Archivable {
	init?(coderRepresentation: AnyObject)
	var coderRepresentation: AnyObject { get }
}

public enum ArchiveStoreError<Value: Archivable where Value: Hashable>: ErrorType {
	case NoSuchEntity(identifier: ArchiveEntity<Value>.Identifier)
	case EntityAlreadyExists(existingEntity: ArchiveEntity<Value>)
	case FactValidationError(fact: ArchiveFact<Value>, onEntity: ArchiveEntity<Value>)
	case TransactionCommitConflict(attemptedTransaction: ArchiveTransaction<Value>)
	case ReadError(storeURL: NSURL)
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
	public init?(coderRepresentation: AnyObject) {
		guard let dictionary = coderRepresentation as? NSDictionary else {
			return nil
		}

		guard let key = dictionary["key"] as? Key else {
			return nil
		}

		guard let archivedValue = dictionary["value"] else {
			return nil
		}

		guard let value = Value(coderRepresentation: archivedValue) else {
			return nil
		}

		self.init(key: key, value: value)
	}

	public var coderRepresentation: AnyObject {
		return [
			"key": self.key,
			"value": self.value.coderRepresentation
		]
	}
}

extension String: Archivable {
	public init?(coderRepresentation: AnyObject) {
		guard let string = coderRepresentation as? String else {
			return nil
		}

		self.init(string)
	}

	public var coderRepresentation: AnyObject {
		return self
	}
}

extension UInt: Archivable {
	public init?(coderRepresentation: AnyObject) {
		guard let number = coderRepresentation as? NSNumber else {
			return nil
		}

		self.init(number)
	}

	public var coderRepresentation: AnyObject {
		return self
	}
}

private func eventWithCoderRepresentation<Value: Archivable>(coderRepresentation: AnyObject) -> Event<ArchiveFact<Value>, ArchiveEntity<Value>.Time>? {
	guard let dictionary = coderRepresentation as? NSDictionary else {
		return nil
	}

	guard let type = dictionary["type"] as? String else {
		return nil
	}

	guard let archivedFact = dictionary["fact"] else {
		return nil
	}

	guard let fact = ArchiveFact<Value>(coderRepresentation: archivedFact) else {
		return nil
	}

	guard let archivedTime = dictionary["time"] else {
		return nil
	}

	guard let time = ArchiveEntity<Value>.Time(coderRepresentation: archivedTime) else {
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

private func coderRepresentationOfEvent<Value: Archivable>(event: Event<ArchiveFact<Value>, ArchiveEntity<Value>.Time>) -> AnyObject {
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

	public var facts: AnyForwardCollection<Fact> {
		return AnyForwardCollection(sortedFactsAssertedInHistory(history))
	}

	public func factsAssertedInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Fact> {
		let filteredHistory = historyInTimeInterval(interval)
		return AnyForwardCollection(sortedFactsAssertedInHistory(filteredHistory))
	}

	public var history: AnyForwardCollection<Event<Fact, Time>> {
		return AnyForwardCollection(events)
	}

	public func historyInTimeInterval(interval: HalfOpenInterval<Time>) -> AnyForwardCollection<Event<Fact, Time>> {
		let filteredEvents = events.filter { interval.contains($0.timestamp) }
		return AnyForwardCollection(filteredEvents)
	}

	public subscript(key: Fact.Key) -> Fact? {
		return factsAssertedInHistory(history)[key].map { event in event.fact }
	}
}

extension ArchiveEntity: Archivable {
	public init?(coderRepresentation: AnyObject) {
		guard let dictionary = coderRepresentation as? NSDictionary else {
			return nil
		}

		guard let identifier = dictionary["identifier"] as? String else {
			return nil
		}

		guard let archivedTime = dictionary["time"] else {
			return nil
		}

		guard let time = Time(coderRepresentation: archivedTime) else {
			return nil
		}

		guard let archivedEvents = dictionary["events"] as? NSArray else {
			return nil
		}

		self.identifier = identifier
		self.creationTimestamp = time

		events = []

		for archivedEvent in archivedEvents {
			guard let event: Event<Fact, Time> = eventWithCoderRepresentation(archivedEvent) else {
				return nil
			}

			events.append(event)
		}
	}

	public var coderRepresentation: AnyObject {
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
			guard let entity = Entity(coderRepresentation: archivedEntity) else {
				return nil
			}

			entitiesByIdentifier[entity.identifier] = entity
		}
	}

	public var entities: AnyForwardCollection<Entity> {
		return AnyForwardCollection(entitiesByIdentifier.values)
	}

	public func entitiesCreatedInTimeInterval(interval: HalfOpenInterval<Entity.Time>) -> AnyForwardCollection<Entity> {
		let filteredEntities = entities.filter { interval.contains($0.creationTimestamp) }
		return AnyForwardCollection(filteredEntities)
	}

	public mutating func createEntity(identifier: Entity.Identifier) throws -> Entity {
		if let existingEntity = entitiesByIdentifier[identifier] {
			throw ArchiveStoreError<Value>.EntityAlreadyExists(existingEntity: existingEntity)
		}

		let entity = Entity(identifier: identifier, creationTimestamp: openedTimestamp)
		entitiesByIdentifier[identifier] = entity
		return entity
	}

	public mutating func assertFact(fact: Entity.Fact, forEntityWithIdentifier identifier: Entity.Identifier) throws {
		guard var entity = entitiesByIdentifier[identifier] else {
			throw ArchiveStoreError<Value>.NoSuchEntity(identifier: identifier)
		}

		guard !entity.facts.contains(fact) else {
			throw ArchiveStoreError<Value>.FactValidationError(fact: fact, onEntity: entity)
		}

		entity.events.append(.Assertion(fact, openedTimestamp))
		entitiesByIdentifier[identifier] = entity
	}

	public mutating func retractFact(fact: Entity.Fact, forEntityWithIdentifier identifier: Entity.Identifier) throws {
		guard var entity = entitiesByIdentifier[identifier] else {
			throw ArchiveStoreError<Value>.NoSuchEntity(identifier: identifier)
		}

		guard entity.facts.contains(fact) else {
			throw ArchiveStoreError<Value>.FactValidationError(fact: fact, onEntity: entity)
		}

		entity.events.append(.Retraction(fact, openedTimestamp))
		entitiesByIdentifier[identifier] = entity
	}

	public subscript(identifier: Entity.Identifier) -> Entity? {
		return entitiesByIdentifier[identifier]
	}
}

public final class ArchiveStore<Value: Archivable where Value: Hashable>: StoreType {
	public typealias Transaction = ArchiveTransaction<Value>

	public let storeURL: NSURL

	private var transactionTimestamp: Transaction.Entity.Time
	private var archivedEntities: NSArray

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
			let timestamp = Transaction.Entity.Time(coderRepresentation: archivedTimestamp)
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
