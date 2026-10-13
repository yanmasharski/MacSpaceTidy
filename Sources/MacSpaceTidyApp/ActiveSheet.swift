enum ActiveSheet: String, Identifiable {
    case confirm
    case progress

    var id: String {
        return rawValue
    }
}
