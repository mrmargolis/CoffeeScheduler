import Foundation
import Testing

@testable import CoffeeCore

/// A store with bean uuid-1 brewed with each of `methods`, in order, a day apart.
private func store(methods: [String]) throws -> CoffeeStore {
    let preparations = methods.enumerated().map { ["name": $1, "config": ["uuid": "prep-\($0)"]] }
    let brews = methods.indices.map { i in
        bcBrew(["method_of_preparation": "prep-\(i)", "config": ["uuid": "brew-\(i)", "unix_timestamp": 1_706_788_800 + i * 86_400]])
    }
    let zip = try makeZip(["Beanconqueror.json": ["BEANS": [bcBean()], "BREWS": brews, "PREPARATION": preparations]])
    let store = try CoffeeStore.inMemory()
    _ = try store.importExport(BeanConquerorParser.parse(zipData: zip, timeZone: utc))
    return store
}

@Suite struct DialInMethodTests {
    @Test func defaultsAreOnForTheFourPourOversByName() {
        for name in ["V60", "Hario V60 02", "Hario Switch", "Hario Alpha", "Orea o1 Steel", "orea v4"] {
            #expect(DialInMethods.isOnByDefault(name), "\(name)")
        }
        for name in ["Cafelat", "xBloom Studio", "Nextlevel Pulsar", "Origami", "Clever Dripper"] {
            #expect(!DialInMethods.isOnByDefault(name), "\(name)")
        }
    }

    @Test func methodsComeFromImportsAToZ() throws {
        let store = try store(methods: ["xBloom Studio", "V60", "Cafelat", "V60"])
        let methods = try store.dialInMethods()
        #expect(methods.map(\.name) == ["Cafelat", "V60", "xBloom Studio"])
        #expect(methods.map(\.isOn) == [false, true, false])
        #expect(methods.allSatisfy { $0.isDefault })
    }

    @Test func aChangedToggleSurvivesAReimport() throws {
        let store = try store(methods: ["V60", "Cafelat"])
        try store.setDialIn(method: "Cafelat", on: true)
        try store.setDialIn(method: "V60", on: false)
        _ = try store.importExport(BeanConquerorParser.parse(zipData: try makeExport(beans: [bcBean()]), timeZone: utc))

        #expect(try store.isDialInMethod("Cafelat"))
        #expect(try store.isDialInMethod("V60") == false)
    }

    @Test func settingTheDefaultForgetsTheOverride() throws {
        let store = try store(methods: ["V60"])
        try store.setDialIn(method: "V60", on: false)
        try store.setDialIn(method: "V60", on: true)
        #expect(try store.dialInMethods().first?.isDefault == true)
    }

    @Test func anUnknownMethodGetsAdvice() throws {
        #expect(try store(methods: []).isDialInMethod(nil))
    }

    @Test func aBagBrewedOnlyWithOffMethodsDoesntGetAdvice() throws {
        #expect(try store(methods: ["Cafelat", "xBloom Studio"]).bagUsesDialInMethod(beanID: "uuid-1") == false)
        #expect(try store(methods: ["Cafelat", "V60"]).bagUsesDialInMethod(beanID: "uuid-1"))
        #expect(try store(methods: []).bagUsesDialInMethod(beanID: "uuid-1"))
    }

    @Test func anEvaluationOnAnOnMethodCounts() throws {
        let store = try store(methods: ["Cafelat"])
        let recipe = CupRecipe(brew: BrewRecipe(method: "Hario Switch"))
        try store.saveEvaluation(CupEvaluation(beanID: "uuid-1", timestamp: 1, date: "2024-02-01", recipe: recipe))
        #expect(try store.bagUsesDialInMethod(beanID: "uuid-1"))
    }
}
