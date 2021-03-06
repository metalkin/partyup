//
//  Tastable.swift
//  PartyUP
//
//  Created by Fritz Vander Heide on 2016-07-03.
//  Copyright © 2016 Sandcastle Application Development. All rights reserved.
//

import Foundation

protocol Tastable: CustomDebugStringConvertible {
	var user: NSUUID { get }
	var alias: String? { get }
	var event: Venue { get }
	var time: NSDate { get }
	var comment: String? { get }
	var media: NSURL { get }
	var debugDescription: String { get }
	var isShareable: Bool { get }
    var via: String { get }
}

extension Tastable   {
	var debugDescription: String { return "User = \(user.UUIDString) alias = \(alias)\nEvent = \(event)\nTimestamp = \(time)\nComment = \(comment)\n" }

	var isShareable: Bool { return false }
    var via: String { return "PartyUp" }
}