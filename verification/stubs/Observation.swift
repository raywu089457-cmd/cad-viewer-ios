// A stub of the Observation module.
//
// `@Observable` is a macro that synthesises change tracking. Stubbing it as an empty macro is
// enough for the app's declarations to parse and type-check; what the macro generates at
// runtime is not something a type check can see anyway.
@attached(member, names: named(init)) public macro Observable() =
    #externalMacro(module: "ObservationMacros", type: "ObservableMacro")

@attached(peer) public macro ObservationIgnored() =
    #externalMacro(module: "ObservationMacros", type: "ObservationIgnoredMacro")
