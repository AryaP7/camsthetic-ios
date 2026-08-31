// SubjectSelectorTests.swift
// CamstheticsEngineTests

import XCTest
@testable import CamstheticsEngine

final class SubjectSelectorTests: XCTestCase {
    func testCandidateScoringWeights() {
        let center = NormPoint(x: 0.5, y: 0.5)
        let rect = NormRect(center: center, width: 0.4, height: 0.4)

        let person = SubjectCandidate(id: "p1", rect: rect, category: .person, confidence: 1.0)
        let animal = SubjectCandidate(id: "a1", rect: rect, category: .animal, confidence: 1.0)
        let object = SubjectCandidate(id: "o1", rect: rect, category: .object, confidence: 1.0)

        let scorePerson = SubjectSelector.scoreCandidate(person)
        let scoreAnimal = SubjectSelector.scoreCandidate(animal)
        let scoreObject = SubjectSelector.scoreCandidate(object)

        XCTAssertGreaterThan(scorePerson, scoreAnimal)
        XCTAssertGreaterThan(scoreAnimal, scoreObject)
    }

    func testStickyLockMaintainsFocusUnderMinorChallenger() {
        var selector = SubjectSelector()

        let person1 = SubjectCandidate(
            id: "person1",
            rect: NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.4, height: 0.4),
            category: .person,
            confidence: 0.9
        )

        // Lock onto person1
        let initial = selector.update(candidates: [person1])
        XCTAssertEqual(initial?.id, "person1")

        // Passerby person2 with slightly higher score (< 0.15 delta)
        let person2 = SubjectCandidate(
            id: "person2",
            rect: NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.42, height: 0.42),
            category: .person,
            confidence: 1.0
        )

        // Over 10 frames, selector sticks with person1
        for _ in 1...10 {
            let selected = selector.update(candidates: [person1, person2])
            XCTAssertEqual(selected?.id, "person1", "Sticky lock should retain person1")
        }
    }

    func testChallengerStealsFocusAfterFourConsecutiveFrames() {
        var selector = SubjectSelector()

        let smallObject = SubjectCandidate(
            id: "obj1",
            rect: NormRect(center: NormPoint(x: 0.2, y: 0.2), width: 0.1, height: 0.1),
            category: .object,
            confidence: 0.6
        )

        // Lock small object
        _ = selector.update(candidates: [smallObject])

        // Large prominent person appears (score delta >> 0.15)
        let bigPerson = SubjectCandidate(
            id: "person1",
            rect: NormRect(center: NormPoint(x: 0.5, y: 0.5), width: 0.5, height: 0.7),
            category: .person,
            confidence: 1.0
        )

        // Frames 1-3: Challenger evaluated, but obj1 retained
        for frame in 1...3 {
            let selected = selector.update(candidates: [smallObject, bigPerson])
            XCTAssertEqual(selected?.id, "obj1", "Frame \(frame) should retain obj1 during challenger evaluation")
        }

        // Frame 4: 4 consecutive frames reached -> person1 takes focus!
        let selected4 = selector.update(candidates: [smallObject, bigPerson])
        XCTAssertEqual(selected4?.id, "person1")
    }
}
