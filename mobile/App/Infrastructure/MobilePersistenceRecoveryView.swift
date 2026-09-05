#if os(iOS)
import PlanBaseCore
import SwiftUI

struct PersistenceRecoveryView: View {
    let details: String
    let retry: () -> Void

    var body: some View {
        PlanBaseRecoveryView(details: details, retry: retry)
    }
}
#endif
