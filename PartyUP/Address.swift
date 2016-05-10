//
//  Address.swift
//  PartyUP
//
//  Created by Fritz Vander Heide on 2016-05-06.
//  Copyright © 2016 Sandcastle Application Development. All rights reserved.
//

import CoreLocation
import LMGeocoder

struct Address: CustomDebugStringConvertible {
	let coordinate: CLLocationCoordinate2D
	let city: String
	let province: String
	let country: String

	var location: CLLocation {
		return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
	}

	init(coordinate: CLLocationCoordinate2D, address: [String:String]) {
		self.coordinate = coordinate
		self.city = address["city"] ?? "Anoncity"
		self.province = address["province"] ?? "Anonstate"
		self.country = address["country"] ?? "Anoncountry"
	}

	init(coordinate: CLLocationCoordinate2D, address: LMAddress) {
		self.coordinate = coordinate
		self.city = address.locality
		self.province = address.administrativeArea
		self.country = address.country
	}

	init(coordinate: CLLocationCoordinate2D, mapkitAddress address: [NSObject:AnyObject]) {
		self.coordinate = coordinate
		self.city = address["City"] as? String ?? address["SubLocality"] as? String ?? "Anoncity"
		self.province = address["State"] as? String ?? "Anonstate"
		self.country = address["Country"] as? String ?? "Anoncountry"
	}

	var debugDescription: String { return "Coordinate: \(coordinate.latitude),\(coordinate.longitude) Address: \(city), \(province), \(country)" }

	static func addressForCoordinates(coordinate: CLLocationCoordinate2D, completionHandler: (Address?, NSError?) -> Void) {
		LMGeocoder().reverseGeocodeCoordinate(coordinate, service: .AppleService) { (places, error) in
			var address: Address?
			if let place = places.first as? LMAddress {
				address = Address(coordinate: coordinate, address: place)
			}
			completionHandler(address, error)
		}
	}
}