import WidgetKit
import SwiftUI

/// Bundle dell'estensione: widget home screen + Live Activity Isola Dinamica.
@main
struct CineFlashWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestNewsWidget()
        NewsActivityWidget()
    }
}
