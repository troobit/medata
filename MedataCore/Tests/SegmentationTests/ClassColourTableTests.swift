import Foundation
import Testing
@testable import Segmentation

// The id->colour table is the single deterministic source for mask overlays,
// §9.2 swatches, and the design pages (UI Design Handoff 00, Decision 15). The
// only contract worth a test is determinism: a class id must map to the same
// colour on every run.
@Suite("ClassColourTable")
struct ClassColourTableTests {

    @Test("Same class id yields the same colour across independent constructions")
    func deterministicAcrossConstructions() {
        let a = ClassColourTable.standard
        let b = ClassColourTable(version: "v0")
        for id in 0..<ClassPalette.standard.totalClasses {
            #expect(a.colour(forClassId: id) == b.colour(forClassId: id))
        }
    }

    @Test("Colour is a pure function of the id (repeat calls are stable)")
    func stableRepeatCalls() {
        let table = ClassColourTable.standard
        for id in 0..<40 {
            #expect(table.colour(forClassId: id) == table.colour(forClassId: id))
        }
    }

    @Test("Components stay within the unit range")
    func componentsInRange() {
        let table = ClassColourTable.standard
        for id in 0..<40 {
            let c = table.colour(forClassId: id)
            #expect(c.red >= 0 && c.red <= 1)
            #expect(c.green >= 0 && c.green <= 1)
            #expect(c.blue >= 0 && c.blue <= 1)
        }
    }

    @Test("Neighbouring class ids get distinguishable colours")
    func neighboursDiffer() {
        let table = ClassColourTable.standard
        #expect(table.colour(forClassId: 0) != table.colour(forClassId: 1))
        #expect(table.colour(forClassId: 5) != table.colour(forClassId: 6))
    }

    @Test("Table carries its palette version")
    func carriesVersion() {
        #expect(ClassColourTable.standard.version == "v0")
    }
}
