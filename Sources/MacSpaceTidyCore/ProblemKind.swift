public enum ProblemKind: String, Sendable {
    case diskNotMounted
    case strayNestedLink
    case brokenLink
    case timeMachineSnapshots
    case lowFreeSpace
}
