/// UI state wrapper shared by every ViewModel.
enum Loadable<Value> {
    case idle, loading, loaded(Value), failed(String)

    var value: Value? { if case .loaded(let v) = self { v } else { nil } }
}
