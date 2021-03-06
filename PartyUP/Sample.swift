//
//  Sample
//  PartyUP
//
//  Created by Fritz Vander Heide on 2015-09-15.
//  Copyright © 2015 Sandcastle Application Development. All rights reserved.
//

import AWSDynamoDB
import AWSCognito

final class Sample: Votable, Equatable
{
	static let RatingUpdateNotification = "SampleRatingUpdateNotification"
	static let VoteUpdateNotification = "SampleVoteUpdateNotification"
	static let FlaggedUpdateNotification = "SampleFlaggedUpdateNotification"

	typealias UsageStamp = UInt8

	let user: NSUUID
    let alias: String?
    unowned let event: Venue
	let time: NSDate
	var comment: String?
    var prefix: String
    
	var rating: [Int] {
		didSet {
			NSNotificationCenter.defaultCenter().postNotificationName(Sample.RatingUpdateNotification, object: self)
		}
	}

	var media: NSURL {
        get { return NSURL(fileURLWithPath: prefix + "/" + user.UUIDString + String(stamp)).URLByAppendingPathExtension("mp4")! }
	}

	var identifier: NSData {
		get {
			var raw = Array<UInt8>(count: 17, repeatedValue: stamp)
			user.getUUIDBytes(&raw)
			return NSData(bytes: &raw, length: raw.count)
		}
	}
    
	var vote = Vote.Meh {
		didSet {
			if oldValue != vote {
				NSNotificationCenter.defaultCenter().postNotificationName(Sample.VoteUpdateNotification, object: self)
			}
		}
	}

	var flag: Bool? {
		didSet {
			if oldValue != flag {
				event.sieveSample(self)
				if oldValue != nil {
					NSNotificationCenter.defaultCenter().postNotificationName(Sample.FlaggedUpdateNotification, object: self)
				}
			}
		}
	}

	var isShareable: Bool { return true }

    init(user: NSUUID, event: Venue, time: NSDate, alias: String?, comment: String?, stamp: UsageStamp, rating: [Int], prefix: String = PartyUpConstants.DefaultStoragePrefix) {
		self.user = user
        self.alias = alias
        self.event = event
		self.time = time
		self.comment = comment
		self.stamp = stamp
		self.rating = rating
        self.prefix = prefix
	}

    convenience init(event: Venue, alias: String? = nil, comment: String? = nil) {
		let stamp = Sample.stamper.next
		self.init(
			user: AuthenticationManager.shared.identity!,
            event: event,
			time: NSDate(),
			alias: alias,
			comment: comment,
			stamp: stamp,
			rating: [0,0],
            prefix: PartyUpConstants.DefaultStoragePrefix
		)
	}

	func setVote(vote: Vote, andFlag flag: Bool = false) {
		if vote != self.vote || flag != self.flag {
			let db = VoteDB()
			db.sample = VoteDB.hashKeyGenerator(event.unique, sample: identifier)
			db.user = VoteDB.rangeKeyGenerator(AuthenticationManager.shared.identity!)
			db.vote = NSNumber(integer: vote.rawValue)
			db.flag = NSNumber(bool: flag)
			AWSDynamoDBObjectMapper.defaultDynamoDBObjectMapper().save(db).continueWithBlock { task in
				if task.error == nil && task.exception == nil {
					if flag == false {
						let upDelta = self.vote == .Up ? -1 : vote == .Up ? 1 : 0
						let downDelta = self.vote == .Down ? -1 : vote == .Down ? 1 : 0
						self.updateRating(upDelta: upDelta, downDelta: downDelta)
					}
					dispatch_async(dispatch_get_main_queue()) {
						self.vote = vote
						self.flag = flag
					}
				}
				return nil
			}
		}
	}

	private func updateRating(upDelta up: Int, downDelta down: Int) {
		if let hash = wrapValue(event.unique), range = wrapValue(identifier), up = wrapValue(up), down = wrapValue(down) {
			let updateInput = AWSDynamoDBUpdateItemInput()
			updateInput.tableName = SampleDB.dynamoDBTableName()
			updateInput.key = ["event" : hash, "id" : range]
			updateInput.updateExpression = "SET ups=if_not_exists(ups,:zero)+:up, downs=if_not_exists(downs,:zero)+:down"
            updateInput.expressionAttributeValues = [":up" : up, ":down" : down, ":zero" : wrapValue(0)!]
			updateInput.returnValues = .UpdatedNew
			AWSDynamoDB.defaultDynamoDB().updateItem(updateInput).continueWithSuccessBlock { (task) in
				if let result = task.result as? AWSDynamoDBUpdateItemOutput {
                    let rate = [Int(result.attributes?["ups"]?.N ?? "0") ?? 0, Int(result.attributes?["downs"]?.N ?? "0") ?? 0]
                    dispatch_async(dispatch_get_main_queue()) {
                        self.rating = rate
                    }
				}

				return nil
			}
		}
	}

	//MARK - Internal Dynamo Representation

    internal convenience init(data: SampleDB, event: Venue) {
		self.init(
			user: NSUUID(UUIDBytes: UnsafePointer(data.id!.bytes)),
            event: event,
			time: NSDate(timeIntervalSince1970: data.time!.doubleValue),
			alias: data.alias,
			comment: data.comment,
			stamp: (UnsafePointer<UInt8>(data.id!.bytes) + 16).memory,
			rating: [data.ups?.integerValue ?? 0, data.downs?.integerValue ?? 0],
            prefix: data.prefix ?? PartyUpConstants.DefaultStoragePrefix
		)

		AWSDynamoDBObjectMapper.defaultDynamoDBObjectMapper().load(VoteDB.self, hashKey: VoteDB.hashKeyGenerator(event.unique, sample: identifier), rangeKey: VoteDB.rangeKeyGenerator(AuthenticationManager.shared.identity!)).continueWithBlock { [weak self] task in
			var vote = Vote.Meh
			var flag = false

			if let result = task.result as? VoteDB {
				vote = Vote(rawValue: result.vote?.integerValue ?? 0)!
				flag = result.flag?.boolValue ?? false
			}

			dispatch_async(dispatch_get_main_queue()) {
				self?.vote = vote
				self?.flag = flag
			}

			return nil
		}
	}

	internal var dynamo: SampleDB {
		get {
			let db = SampleDB()
			db.time = time.timeIntervalSince1970
			db.alias = alias
			db.comment = comment
			db.id = identifier
            db.event = event.unique
			db.ups = rating[0]
			db.downs = rating[1]
            db.prefix = prefix == PartyUpConstants.DefaultStoragePrefix ? nil : prefix

			return db
		}
	}

	internal class SampleDB: AWSDynamoDBObjectModel, AWSDynamoDBModeling
	{
		var id: NSData?
		var event: String?
		var time: NSNumber?
        var alias: String?
		var comment: String?
		var ups: NSNumber?
		var downs: NSNumber?
        var prefix: String?

		@objc static func dynamoDBTableName() -> String {
			return "Samples"
		}

		@objc static func hashKeyAttribute() -> String {
			return "event"
		}

		@objc static func rangeKeyAttribute() -> String {
			return "id"
		}
	}

	//MARK - Internal Stamp Factory

	private let stamp: UsageStamp

	private class StampFactory
	{
		private var data: AWSCognitoDataset?

		init() {
			NSNotificationCenter.defaultCenter().addObserverForName(AuthenticationManager.AuthenticationStatusChangeNotification, object: nil, queue: NSOperationQueue.mainQueue()) { [weak self] note in
				if let me = self, state = note.userInfo?["new"] as? Int where AuthenticationState(rawValue: state) == .Authenticated  {
					me.data = AWSCognito.defaultCognito().openOrCreateDataset("SampleStamp")
					me.data?.synchronizeOnConnectivity().continueWithBlock { task in
						return nil
					}
				}
			}
		}

		var next: UsageStamp {
			let current = UsageStamp(data?.stringForKey("counter") ?? "0") ?? 0
			data?.setString("\(current &+ 1)", forKey: "counter")
			data?.synchronizeOnConnectivity().continueWithBlock { task in
				return nil
			}

			return current
		}
	}

	private static var stamper: StampFactory!

	static func InitializeStamps() {
		stamper = StampFactory()
	}
    
    //MARK - Internal Dynamo Vote
    
    internal class VoteDB: AWSDynamoDBObjectModel, AWSDynamoDBModeling
    {
        var sample: NSData?
        var user: NSData?
        var vote: NSNumber?
		var flag: NSNumber?
        
        @objc static func dynamoDBTableName() -> String {
            return "Votes"
        }
        
        @objc static func hashKeyAttribute() -> String {
            return "sample"
        }
        
        @objc static func rangeKeyAttribute() -> String {
            return "user"
        }
        
        static func hashKeyGenerator(event: String, sample: NSData) -> NSData {
            let combined = NSMutableData(data: sample)
            combined.appendData(event.dataUsingEncoding(NSUTF8StringEncoding)!)
            return combined
        }
        
        static func rangeKeyGenerator(user: NSUUID) -> NSData {
            let raw = Array<UInt8>(count: 16, repeatedValue: 0)
            user.getUUIDBytes(UnsafeMutablePointer<UInt8>(raw))
            return NSData(bytes: raw, length: raw.count)
        }
    }
}

func ==(lhs: Sample, rhs: Sample) -> Bool {
	return (lhs.user == rhs.user) && (lhs.event == rhs.event) && (lhs.stamp == rhs.stamp)
}
