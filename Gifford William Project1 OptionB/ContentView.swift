import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = OneFactViewModel()

    var body: some View {
        RootTabView(viewModel: viewModel)
            .preferredColorScheme(.light)
            .tint(AppTheme.accent)
    }
}
