import Foundation
import Combine

final class HistoryViewModel: ObservableObject {
    @Published var runs: [Run] = []
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        DataStore.shared.$runs
            .receive(on: DispatchQueue.main)
            .assign(to: &$runs)
    }
} 