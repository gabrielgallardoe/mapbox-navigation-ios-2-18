import UIKit
import MapboxDirections
import MapboxCoreNavigation
import MapboxMaps
import Turf
import CoreLocation

/// A components, designed to help manage `NavigationMapView` ornaments logic.
class OrnamentsController: NavigationComponent, NavigationComponentDelegate {
    
    // MARK: Lifecycle Management
    
    weak var navigationViewData: NavigationViewData!
    weak var eventsManager: NavigationEventsManager!
    
    fileprivate var navigationView: NavigationView {
        return navigationViewData.navigationView
    }
    
    fileprivate var navigationMapView: NavigationMapView {
        return navigationViewData.navigationView.navigationMapView
    }
    
    init(_ navigationViewData: NavigationViewData, eventsManager: NavigationEventsManager) {
        self.navigationViewData = navigationViewData
        self.eventsManager = eventsManager
    }
    
    private func resumeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationDidChange(_:)),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdateRoadNameFromStatus),
                                               name: .currentRoadNameDidChange,
                                               object: nil)
    }
    
    private func suspendNotifications() {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIDevice.orientationDidChangeNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: .currentRoadNameDidChange,
                                                  object: nil)
    }
    
    @objc func orientationDidChange(_ notification: Notification) {
        updateMapViewOrnaments()
    }
    
    func embedBanners(topBanner: ContainerViewController, bottomBanner: ContainerViewController) {
        let topContainer = navigationViewData.navigationView.topBannerContainerView
        
        embed(topBanner, in: topContainer) { (parent, banner) -> [NSLayoutConstraint] in
            banner.view.translatesAutoresizingMaskIntoConstraints = false
            return banner.view.constraintsForPinning(to: self.navigationViewData.navigationView.topBannerContainerView)
        }
        
        topContainer.backgroundColor = .clear
        
        let bottomContainer = navigationViewData.navigationView.bottomBannerContainerView
        embed(bottomBanner, in: bottomContainer) { (parent, banner) -> [NSLayoutConstraint] in
            banner.view.translatesAutoresizingMaskIntoConstraints = false
            return banner.view.constraintsForPinning(to: self.navigationViewData.navigationView.bottomBannerContainerView)
        }
        
        bottomContainer.backgroundColor = .clear
        
        navigationViewData.containerViewController.view.bringSubviewToFront(navigationViewData.navigationView.topBannerContainerView)
    }
    
    private func embed(_ child: UIViewController, in container: UIView, constrainedBy constraints: ((UIViewController, UIViewController) -> [NSLayoutConstraint])?) {
        child.willMove(toParent: navigationViewData.containerViewController)
        navigationViewData.containerViewController.addChild(child)
        container.addSubview(child.view)
        if let childConstraints: [NSLayoutConstraint] = constraints?(navigationViewData.containerViewController, child) {
            navigationViewData.containerViewController.view.addConstraints(childConstraints)
        }
        child.didMove(toParent: navigationViewData.containerViewController)
    }
    
    // MARK: Feedback Collection
    
    var detailedFeedbackEnabled: Bool = false
    
    @objc func feedback(_ sender: Any) {
        let parent = navigationViewData.containerViewController
        let feedbackViewController = FeedbackViewController(eventsManager: eventsManager)
        feedbackViewController.detailedFeedbackEnabled = detailedFeedbackEnabled
        parent.present(feedbackViewController, animated: true)
    }
    
    // MARK: Map View Ornaments Handlers
    
    var showsSpeedLimits: Bool = true {
        didSet {
            navigationView.speedLimitView.isAlwaysHidden = !showsSpeedLimits
        }
    }
    
    var floatingButtonsPosition: MapOrnamentPosition? {
        get {
            return navigationView.floatingButtonsPosition
        }
        set {
            if let newPosition = newValue {
                navigationView.floatingButtonsPosition = newPosition
            }
        }
    }
    
    var floatingButtons: [UIButton]? {
        get {
            return navigationView.floatingButtons
        }
        set {
            navigationView.floatingButtons = newValue
        }
    }
    
    var reportButton: FloatingButton {
        return navigationView.reportButton
    }
    
    @objc func toggleMute(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        let muted = sender.isSelected
        NavigationSettings.shared.voiceMuted = muted
    }
    
    /**
     Method updates `logoView` and `attributionButton` margins to prevent incorrect alignment
     reported in https://github.com/mapbox/mapbox-navigation-ios/issues/2561.
     */
    private func updateMapViewOrnaments() {
        let bottomBannerHeight = navigationViewData.navigationView.bottomBannerContainerView.bounds.height
        let bottomBannerVerticalOffset = navigationViewData.navigationView.bounds.height - bottomBannerHeight - navigationViewData.navigationView.bottomBannerContainerView.frame.origin.y
        let defaultOffset: CGFloat = 10.0
        let x: CGFloat = defaultOffset
        let y: CGFloat = bottomBannerHeight + defaultOffset + bottomBannerVerticalOffset
        
        if #available(iOS 11.0, *) {
            navigationMapView.mapView.ornaments.options.logo.margins = CGPoint(x: x, y: y - navigationView.safeAreaInsets.bottom)
        } else {
            navigationMapView.mapView.ornaments.options.logo.margins = CGPoint(x: x, y: y)
        }
        
        if #available(iOS 11.0, *) {
            navigationMapView.mapView.ornaments.options.attributionButton.margins = CGPoint(x: x, y: y - navigationView.safeAreaInsets.bottom)
        } else {
            navigationMapView.mapView.ornaments.options.attributionButton.margins = CGPoint(x: x, y: y)
        }
    }
    
    // MARK: Road Labelling
    
    typealias LabelRoadNameCompletionHandler = (_ defaultRoadNameAssigned: Bool) -> Void
    
    var labelRoadNameCompletionHandler: (LabelRoadNameCompletionHandler)?
    
    var roadNameFromStatus: String?
    
    @objc func didUpdateRoadNameFromStatus(_ notification: Notification) {
        roadNameFromStatus = notification.userInfo?[RouteController.NotificationUserInfoKey.roadNameKey] as? String
    }
    
    /**
     Updates the current road name label to reflect the road on which the user is currently traveling.
     
     - parameter at: The user’s current location as provided by the system location management system. This has less priority then `snappedLocation` (see below) and is used only if method will attempt to resolve road name automatically.
     - parameter suggestedName: The road name to put onto label. If not provided - method will attempt to extract the closest road name from map features.
     - parameter snappedLocation: User's location, snapped to the road network. Has higher priority then `at` location.
     */
    func labelCurrentRoad(at rawLocation: CLLocation, suggestedName roadName: String?, for snappedLocation: CLLocation? = nil) {
        guard navigationView.resumeButton.isHidden else { return }
        
        if let roadName = roadName {
            navigationView.wayNameView.text = roadName.nonEmptyString
            navigationView.wayNameView.containerView.isHidden = roadName.isEmpty
            
            return
        }
        
        navigationMapView.labelCurrentRoadFeature(at: snappedLocation ?? rawLocation,
                                                  router: navigationViewData.router,
                                                  wayNameView: navigationView.wayNameView,
                                                  roadNameFromStatus: roadNameFromStatus)
        
        if let labelRoadNameCompletionHandler = labelRoadNameCompletionHandler {
            labelRoadNameCompletionHandler(true)
        }
    }
    
    // MARK: NavigationComponentDelegate implementation
    
    func navigationViewDidLoad(_: UIView) {
        navigationViewData.navigationView.muteButton.addTarget(self, action: #selector(toggleMute(_:)), for: .touchUpInside)
        navigationViewData.navigationView.reportButton.addTarget(self, action: #selector(feedback(_:)), for: .touchUpInside)
    }
    
    func navigationViewWillAppear(_: Bool) {
        resumeNotifications()
        navigationViewData.navigationView.muteButton.isSelected = NavigationSettings.shared.voiceMuted
    }
    
    func navigationViewDidDisappear(_: Bool) {
        suspendNotifications()
    }
    
    func navigationViewDidLayoutSubviews() {
        updateMapViewOrnaments()
    }
    
    // MARK: NavigationComponent implementation
    
    func navigationService(_ service: NavigationService, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
        
        navigationViewData.navigationView.speedLimitView.signStandard = progress.currentLegProgress.currentStep.speedLimitSignStandard
        navigationViewData.navigationView.speedLimitView.speedLimit = progress.currentLegProgress.currentSpeedLimit
    }
}
