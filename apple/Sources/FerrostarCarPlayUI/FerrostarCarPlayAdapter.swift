import CarPlay
import Combine
import FerrostarCore
import FerrostarCoreFFI
import FerrostarSwiftUI

@MainActor
class FerrostarCarPlayAdapter: NSObject {
    // TODO: This should be customizable. For now we're just ignore it.
    @Published var uiState: CarPlayUIState = .idle(nil)
    @Published var currentRoute: CPTrip?

    private let ferrostarCore: FerrostarCore
    private let formatterCollection: FormatterCollection
    private let distanceUnits: MKDistanceFormatter.Units

    /// The MapTemplate hosts both the idle and navigating templates.
    private var mapTemplate: CPMapTemplate?
    private var idleTemplate: IdleMapTemplate?
    private var navigatingTemplate: NavigatingTemplateHost?
    private var searchTemplate: CPSearchTemplate?

    var currentSession: CPNavigationSession?
    var currentTrip: CPTrip?

    private var cancellables = Set<AnyCancellable>()

    init(
        ferrostarCore: FerrostarCore,
        formatterCollection: FormatterCollection = FoundationFormatterCollection(),
        distanceUnits: MKDistanceFormatter.Units = .default
    ) {
        self.ferrostarCore = ferrostarCore
        self.formatterCollection = formatterCollection
        self.distanceUnits = distanceUnits

        super.init()
        setupIdleTemplate()
    }

    func setup(
        on mapTemplate: CPMapTemplate,
        showCentering: Bool,
        onCenter: @escaping () -> Void,
        onStartTrip: @escaping () -> Void,
        onCancelTrip: @escaping () -> Void
    ) {
        self.mapTemplate = mapTemplate
        
        navigatingTemplate = NavigatingTemplateHost(
            mapTemplate: mapTemplate,
            formatters: formatterCollection,
            units: distanceUnits,
            showCentering: showCentering,
            onCenter: onCenter,
            onStartTrip: onStartTrip,
            onCancelTrip: onCancelTrip
        )
        
        setupObservers()
    }

    // Add this function to initialize the idle template
    func setupIdleTemplate() {
        // TODO: Review https://developer.apple.com/carplay/documentation/CarPlay-App-Programming-Guide.pdf
        //       Page 37 of 65 - we probably want the default idle template to be a trip preview w/ start nav.
        idleTemplate = IdleMapTemplate()

        idleTemplate?.onSearchButtonTapped = { [weak self] in
            self?.showSearchInterface()
        }

        idleTemplate?.onRecenterButtonTapped = { [weak self] in
            self?.recenterMap()
        }

        idleTemplate?.onStartNavigationButtonTapped = { [weak self] in
            self?.startNavigation()
        }
        
        idleTemplate?.onTripPreviewTapped = { [weak self] in
            self?.showTripPreview()
        }
    }

    private func showTripPreview() {
        idleTemplate?.showTripPreview()
    }

    private func showSearchInterface() {
        guard let mapTemplate = mapTemplate else { return }
        
        let searchTemplate = CPSearchTemplate()
        searchTemplate.delegate = self
        
        uiState = .searching
        mapTemplate.presentTemplate(searchTemplate, animated: true)
        self.searchTemplate = searchTemplate
    }
    
    private func recenterMap() {
        guard let mapTemplate = mapTemplate else { return }
        mapTemplate.showPanningInterface(animated: true)
    }
    
    private func startNavigation() {
        guard let trip = currentTrip else {
            uiState = .error("No route selected")
            return
        }
        
        do {
            try navigatingTemplate?.start(routes: [trip], waypoints: [])
            uiState = .navigating
        } catch {
            uiState = .error("Failed to start navigation: \(error.localizedDescription)")
        }
    }

    private func setupObservers() {
        // Handle Navigation Start/Stop
        Publishers.CombineLatest(
            ferrostarCore.$route,
            ferrostarCore.$state
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] route, navState in
            guard let self else { return }
            guard let navState else {
                if case let .navigating = self.uiState {
                    navigatingTemplate?.cancelTrip()
                }
                return
            }

            switch navState.tripState {
            case .navigating:
                if let route, uiState != .navigating {
                    uiState = .navigating
                    do {
                        try navigatingTemplate?.start(routes: [route], waypoints: route.waypoints)
                    } catch {
                        uiState = .error("Failed to start navigation: \(error.localizedDescription)")
                    }
                }
                navigatingTemplate?.update(navigationState: navState)
            case .complete:
                navigatingTemplate?.completeTrip()
                uiState = .idle(nil)
            case .idle:
                break
            }
        }
        .store(in: &cancellables)

        // Update trip preview when route changes
        ferrostarCore.$route
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                guard let self else { return }
                if let route {
                    // Convert Ferrostar route to CPTrip
                    let trip = self.convertToCPTrip(route)
                    self.currentTrip = trip
                    self.idleTemplate?.updateTripPreview(trip)
                } else {
                    self.currentTrip = nil
                    self.idleTemplate?.updateTripPreview(nil)
                }
            }
            .store(in: &cancellables)

        ferrostarCore.$state
            .receive(on: DispatchQueue.main)
            .compactMap { navState -> (VisualInstruction, RouteStep)? in
                guard let instruction = navState?.currentVisualInstruction,
                      let step = navState?.currentStep
                else {
                    return nil
                }

                return (instruction, step)
            }
            .removeDuplicates(by: { $0.0 == $1.0 })
            .sink { [weak self] instruction, step in
                guard let self else { return }

                navigatingTemplate?.update(instruction, currentStep: step)
            }
            .store(in: &cancellables)
    }

    private func convertToCPTrip(_ route: Route) -> CPTrip {
        // Create trip origin and destination
        let origin = MKMapItem(placemark: MKPlacemark(
            coordinate: route.waypoints.first?.coordinate ?? CLLocationCoordinate2D(),
            addressDictionary: nil
        ))
        
        let destination = MKMapItem(placemark: MKPlacemark(
            coordinate: route.waypoints.last?.coordinate ?? CLLocationCoordinate2D(),
            addressDictionary: nil
        ))
        
        // Create trip
        let trip = CPTrip(origin: origin, destination: destination, routeChoices: [])
        
        // Add route choices if available
        if let alternatives = route.alternatives {
            trip.routeChoices = alternatives.map { alternative in
                let choice = CPRouteChoice(summaryVariants: [alternative.summary])
                choice.userInfo = alternative
                return choice
            }
        }
        
        return trip
    }
}

// MARK: - CPSearchTemplateDelegate
extension FerrostarCarPlayAdapter: CPSearchTemplateDelegate {
    func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String, completionHandler: @escaping ([CPSearchTemplate.SearchResult]) -> Void) {
        guard !searchText.isEmpty else {
            completionHandler([])
            return
        }
        
        Task {
            do {
                let results = try await ferrostarCore.geocode(query: searchText)
                let searchResults = results.map { result in
                    let item = MKMapItem(placemark: MKPlacemark(
                        coordinate: result.coordinate,
                        addressDictionary: nil
                    ))
                    item.name = result.name
                    return CPSearchTemplate.SearchResult(item: item, text: result.name)
                }
                completionHandler(searchResults)
            } catch {
                print("Geocoding error: \(error)")
                completionHandler([])
            }
        }
    }
    
    func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPSearchTemplate.SearchResult, completionHandler: @escaping () -> Void) {
        guard let coordinate = item.item.placemark.location?.coordinate else {
            completionHandler()
            return
        }
        
        Task {
            do {
                // Calculate route to selected location
                let route = try await ferrostarCore.calculateRoute(
                    from: ferrostarCore.currentLocation ?? CLLocationCoordinate2D(),
                    to: coordinate
                )
                
                // Update UI state and show trip preview
                await MainActor.run {
                    let trip = convertToCPTrip(route)
                    currentTrip = trip
                    idleTemplate?.updateTripPreview(trip)
                    uiState = .previewingRoute(trip)
                }
                
                mapTemplate?.dismissTemplate(animated: true)
                completionHandler()
            } catch {
                await MainActor.run {
                    uiState = .error("Failed to calculate route: \(error.localizedDescription)")
                }
                completionHandler()
            }
        }
    }
    
    func searchTemplateSearchCancelled(_ searchTemplate: CPSearchTemplate) {
        mapTemplate?.dismissTemplate(animated: true)
        uiState = .idle(nil)
    }
}
