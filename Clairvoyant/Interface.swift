//
//  Data.swift
//  Clairvoyant
//
//  Created by Justin Spahr-Summers on 2015-07-11.
//  Copyright © 2015 Justin Spahr-Summers. All rights reserved.
//

import Foundation

public enum FactStatus: Equatable {
	case Unsaved
	case Saved
	case Retracted
}

public protocol FactType: Equatable {
	typealias Key: Equatable
	typealias Value: Equatable

	var status: FactStatus { get }
	var value: Value { get }
}

public protocol EntityType: Equatable {
	typealias Identifier: Equatable

	var identifier: Identifier { get }

	subscript<F: FactType>(key: F.Key) -> F.Value? { get }

	mutating func addFact<F: FactType>(fact: F) throws
	mutating func retractFact<F: FactType>(fact: F)
}

public protocol GenerationType {
	typealias Entity: EntityType
	typealias Index: ForwardIndexType

	subscript(entityID: Entity.Identifier) -> Entity? { get }
}

public protocol TransactionType: GenerationType {
	func insertEntityWithFacts(facts: [Entity.Fact.Key: Entity.Fact.Value]) throws -> Entity

	subscript(entityID: Entity.Identifier) -> Entity? { get set }
}

public protocol StoreType {
	typealias Transaction: TransactionType

	func factsAboutEntity<T>(entity: Transaction.Entity, asOfTransactionID: Transaction.Identifier? = nil) throws -> [Fact<T>]

	func openTransaction() -> Transaction
	func saveTransaction(transaction: Transaction) throws -> Transaction.Identifier
}
