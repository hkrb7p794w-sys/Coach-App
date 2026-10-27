import Foundation
import Testing

@testable import CoachCore

struct UserSourcesTests {
  let sleep = UserSource(
    citation: "Walker 2024", reference: "10.1000/xyz", statement: "Mehr Schlaf verbessert die Sprintleistung.",
    topics: [.recovery])
  let protein = UserSource(
    citation: "Morton et al. 2018", reference: "PMID: 28698222",
    statement: "Über 1,6 g Protein je kg brachte kaum zusätzlichen Muskelzuwachs.", topics: [.nutrition, .strength])

  @Test func injectsMatchingSourcesAfterAppRules() {
    let input: [String: JSONValue] = [
      "evidence": .array([.object(["id": .string("gym.volume"), "statement": .string("Mehr Sätze.")])])
    ]
    let gym = UserSources.inject([sleep, protein], into: input, task: "gym_hints")
    let ids = gym["evidence"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
    #expect(ids == ["gym.volume", sleep.evidenceID, protein.evidenceID])
    let statement = gym["evidence"]?.arrayValue?.last?["statement"]?.stringValue
    #expect(statement?.hasSuffix("(eigene Quelle: Morton et al. 2018)") == true)

    let nutrition = UserSources.inject([sleep, protein], into: input, task: "nutrition_review")
    #expect(nutrition["evidence"]?.arrayValue?.count == 2)
    let chat = UserSources.inject([sleep, protein], into: [:], task: "coach_chat")
    #expect(chat["evidence"]?.arrayValue?.count == 2)
    #expect(UserSources.inject([sleep], into: input, task: "meal_analyze") == input)
  }

  @Test func linksAndValidity() {
    #expect(sleep.url?.absoluteString == "https://doi.org/10.1000/xyz")
    #expect(protein.url?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/28698222/")
    #expect(UserSource(citation: "", statement: "zu kurz").isValid == false)
    #expect(UserSources.isUserID(sleep.evidenceID))
    let answer = JSONValue.object(["quellen": .array([.string(sleep.evidenceID), .string("erfunden")])])
    #expect(CoachingNote.sources(from: answer) == [sleep.evidenceID])
  }
}
