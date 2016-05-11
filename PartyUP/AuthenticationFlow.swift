//
//  AuthenticationFlow.swift
//  PartyUP
//
//  Created by Fritz Vander Heide on 2016-04-25.
//  Copyright © 2016 Sandcastle Application Development. All rights reserved.
//

import SCLAlertView

typealias AuthenticationFlowCompletion = (AuthenticationManager) -> Void

class AuthenticationFlow {

	private(set) var isFlowing = false
    
    func addAction(action: AuthenticationFlowCompletion) {
        completers.append(action)
    }
    
    func startOnController(controller: UIViewController) -> AuthenticationFlow {
        if !isFlowing {
            isFlowing = true
            beginOnController(controller)
        }
        return self
    }
    
    func stop() {
        if let leader = leader {
            leader.close()
            AuthenticationFlow.flow = nil
        }
    }

	private func beginOnController(controller: UIViewController) {
        let alert = SCLAlertView(appearance: SCLAlertView.SCLAppearance(showCloseButton: false, shouldAutoDismiss: false))
        let inLabel = NSLocalizedString("Log in with", comment: "Login service button label")
        let outLabel = NSLocalizedString("Log out of", comment: "Logout service button label")
        for auth in manager.authentics {
            let label = "  " + (auth.isLoggedIn ? outLabel : inLabel) + " \(auth.name)"
            let button = alert.addButton(label, backgroundColor: auth.color) {
                [unowned alert] in alert.hideView()
                self.manager.loginToProvider(auth, fromViewController: controller)
            }
            button.setImage(auth.logo, forState: .Normal)
        }
        alert.addButton(NSLocalizedString("Read Terms of Service", comment: "Terms alert full terms action")) { UIApplication.sharedApplication().openURL(NSURL(string: "terms.html", relativeToURL: PartyUpConstants.PartyUpWebsite)!)
        }
        alert.addButton(NSLocalizedString("Let me think about it", comment: "Login putoff"), action: AuthenticationFlow.stop(self))
        
        let file = NSBundle.mainBundle().pathForResource("Conduct", ofType: "txt")
        let message: String? = file.flatMap { try? String.init(contentsOfFile: $0) }
        leader = alert.showNotice(NSLocalizedString("Log in", comment: "Login Title"),
                                  subTitle: message!,
                                  colorStyle: 0xf77e56)
	}

	private func end() {
        stop()
        self.completers.forEach { $0(self.manager) }
	}

    init() {
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AuthenticationFlow.observeAuthenticationNotification(_:)), name: AuthenticationManager.AuthenticationStatusChangeNotification, object: manager)
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	@objc
	func observeAuthenticationNotification(note: NSNotification) {
		if let raw = note.userInfo?["new"] as? Int, let state = AuthenticationState(rawValue: raw) {
			switch state {
			case .Authenticated:
				alertSuccessWithTitle(NSLocalizedString("Logged In", comment: "Logged in alert title"),
				                                 andDetail: NSLocalizedString("Party Hearty!", comment: "Logged in alert detail"),
				                                 closeLabel: nil, dismissHandler: AuthenticationFlow.end(self))
			case .Unauthenticated:
				alertFailureWithTitle(NSLocalizedString("Not Logged In", comment: "Not logged in alert title"),
				                                 andDetail: NSLocalizedString("Better luck next time.", comment: "Not logged in alert detail"),
				                                 closeLabel: nil, dismissHandler: AuthenticationFlow.end(self) )
			case .Transitioning:
				break
			}
		}
	}

	private let manager = AuthenticationManager.shared
	private var leader: SCLAlertViewResponder?
	private var completers = [AuthenticationFlowCompletion]()

    static var shared: AuthenticationFlow {
        flow = flow ?? AuthenticationFlow()
		return flow!
	}

	private static var flow: AuthenticationFlow?
}
