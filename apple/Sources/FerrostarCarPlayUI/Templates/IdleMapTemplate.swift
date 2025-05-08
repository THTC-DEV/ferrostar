import CarPlay
import MapKit

// TODO: This has yet to be tested/used, but it's here as a starting point for the default idle.
public class IdleMapTemplate: CPMapTemplate {
    private var searchButton: CPBarButton?
    private var recenterButton: CPMapButton?
    private var startNavigationButton: CPMapButton?
    private var tripPreviewButton: CPBarButton?

    public var onSearchButtonTapped: (() -> Void)?
    public var onRecenterButtonTapped: (() -> Void)?
    public var onStartNavigationButtonTapped: (() -> Void)?
    public var onTripPreviewTapped: (() -> Void)?

    private var currentTrip: CPTrip?
    
    @available(iOS 14.0, *)
    private var tripPreviewTemplate: CPTripPreviewTemplate?

    // MARK: - Initialization

    override public init() {
        super.init()
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Configuration

    private func setupUI() {
        // Configure search button
        searchButton = CPBarButton(title: "Search", handler: { [weak self] _ in
            self?.onSearchButtonTapped?()
        })

        // Configure trip preview button
        tripPreviewButton = CPBarButton(title: "Preview", handler: { [weak self] _ in
            self?.onTripPreviewTapped?()
        })

        leadingNavigationBarButtons = [searchButton, tripPreviewButton].compactMap { $0 }

        // Configure map buttons
        setupMapButtons()

        // Configure general template properties
        automaticallyHidesNavigationBar = false
        hidesButtonsWithNavigationBar = false
    }

    private func setupMapButtons() {
        // Recenter button
        recenterButton = CPMapButton { [weak self] _ in
            self?.onRecenterButtonTapped?()
        }
        recenterButton?.image = UIImage(systemName: "location")

        // Start navigation button (hidden by default)
        startNavigationButton = CPMapButton { [weak self] _ in
            self?.onStartNavigationButtonTapped?()
        }
        startNavigationButton?.image = UIImage(systemName: "arrow.triangle.turn.up.right.diamond")
        startNavigationButton?.isHidden = true

        mapButtons = [recenterButton, startNavigationButton].compactMap { $0 }
    }

    // MARK: - Public Interface

    public func showStartNavigationButton(_ show: Bool) {
        startNavigationButton?.isHidden = !show
    }

    public func updateStartNavigationButtonImage(_ image: UIImage?) {
        startNavigationButton?.image = image
    }

    public func updateTripPreview(_ trip: CPTrip?) {
        currentTrip = trip
        tripPreviewButton?.isEnabled = trip != nil
    }

    public func showTripPreview() {
        guard let trip = currentTrip else { return }
        
        // Show the trip preview using CPMapTemplate's built-in preview functionality
        showTripPreviews([trip], textConfiguration: nil)
    }
}

// MARK: - CPMapTemplateDelegate
extension IdleMapTemplate: CPMapTemplateDelegate {
    public func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        // Start navigation with the selected trip
        onStartNavigationButtonTapped?()
    }
    
    public func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
        // Handle navigation cancellation
    }
}
