import SwiftUI

struct BrowseView: View {
    var body: some View {
        VStack {
            CustomTitle(title: "Browse")
            Spacer()
            Text("TODO: Browse")
            Spacer()
        }
    }
}

#if DEBUG
struct BrowseView_Previews: PreviewProvider {
    static var previews: some View {
        BrowseView()
    }
}
#endif
