import SwiftUI

@main
struct TeslaDashApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
