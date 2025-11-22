# Back button interception audit

This document summarizes every back-button interception point in the app and the behavior implemented in each place.

## Widget-level helper
- `lib/widgets/double_back_to_exit.dart`
  - Wraps any child with a `WillPopScope` that shows a snackbar prompt on first back press and exits the app on Android when pressed again within the interval. If the nested navigator can pop, it allows the pop immediately.

## Screen-level handling
- `lib/screens/main_screen.dart`
  - Uses a root-level `WillPopScope` to coordinate navigation between tabs and double-back-to-exit behavior. When on the catalog tab (index 0), back first attempts to delegate to the catalog/collections container and otherwise switches the tab instead of popping. On the other tab it shows a snackbar prompt and exits on the second press (Android only).
- `lib/screens/catalog_and_collections_screen.dart`
  - Intercepts back to keep navigation within the catalog/collections stack. Back switches from the “Series” tab to “Genres”, or, when already on “Genres”, asks the child `GenresScreen` to clear the selected genre (scrolling to top) before permitting a pop.
- `lib/screens/genres_screen.dart`
  - Handles back to clear the selected genre or trigger the optional `onReturnToMain` callback instead of popping immediately. Only allows the pop when there is nothing to reset.

## Notes
- No other screens intercept the system back button at this time. The above scopes cover the main navigation flow and catalog-related stacks where custom handling is needed.
