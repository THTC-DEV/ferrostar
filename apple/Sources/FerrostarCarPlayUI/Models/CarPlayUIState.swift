import CarPlay

enum CarPlayUIState: Equatable {
    /// The idle map template should display the map before use.
    ///
    /// It accepts an optional template since it typically will require customization
    /// by the implementing app to do more than just show the map and start nav.
    case idle(CPTemplate?)

    /// The Ferrostar supplied navigation template.
    case navigating

    /// The search interface is being displayed
    case searching

    /// A route preview is being displayed
    case previewingRoute(CPTrip)

    /// An error has occurred
    case error(String)

    /// The app is loading or processing
    case loading

    // TODO: What other cases should we offer for configuration?
}
