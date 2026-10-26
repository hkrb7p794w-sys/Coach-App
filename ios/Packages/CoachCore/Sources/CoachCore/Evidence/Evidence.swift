import Foundation

/// Eine Veröffentlichung, auf die sich eine Regel stützt. DOIs am 26.10.2026 in PubMed geprüft.
public struct Study: Equatable, Sendable, Identifiable {
  public enum Kind: String, Sendable {
    case metaAnalysis = "Metaanalyse"
    case systematicReview = "Systematisches Review"
    case review = "Review"
    case consensus = "Konsens/Leitlinie"
    case trial = "Randomisierte Studie"
    case cohort = "Kohortenstudie"
    case study = "Studie"
  }

  public let id: String
  /// „Helgerud et al. 2007“
  public let citation: String
  public let title: String
  public let journal: String
  public let doi: String?
  public let pmid: String
  public let kind: Kind

  public var url: URL? {
    if let doi { return URL(string: "https://doi.org/\(doi)") }
    return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/")
  }
}

/// Eine Regel der App mit ihrer Begründung.
public struct EvidenceRule: Equatable, Sendable, Identifiable {
  /// Wie gut die Regel gestützt ist – ehrlich statt Pseudo-Präzision.
  public enum Strength: String, Sendable {
    /// Metaanalysen, systematische Reviews oder Leitlinien stützen die Aussage direkt.
    case strong = "gut belegt"
    /// Einzelstudien oder Reviews stützen die Richtung; Schwellenwerte sind Praxiswerte.
    case moderate = "belegt, Schwellen aus der Praxis"
    /// Praxisregel: plausibel und vorsichtig, aber ohne direkte Studie für genau diesen Wert.
    case practice = "Praxisregel"
  }

  public let id: String
  public let title: String
  /// Kernaussage in einem Satz – dieser Satz geht auch an die KI.
  public let statement: String
  public let strength: Strength
  public let studyIDs: [String]

  public var studies: [Study] { studyIDs.compactMap { Evidence.studiesByID[$0] } }
}

/// Alle Quellen und Regeln an einer Stelle. Neue Regeln nur mit geprüfter Quelle (PubMed/DOI) ergänzen.
public enum Evidence {
  // swift-format-ignore
  public static let studies: [Study] = [
    Study(id: "plews2012", citation: "Plews et al. 2012", title: "Heart rate variability in elite triathletes, is variation in variability the key to effective training? A case comparison.", journal: "Eur J Appl Physiol", doi: "10.1007/s00421-012-2354-4", pmid: "22367011", kind: .study),
    Study(id: "plews2013", citation: "Plews et al. 2013", title: "Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring.", journal: "Sports Med", doi: "10.1007/s40279-013-0071-8", pmid: "23852425", kind: .review),
    Study(id: "buchheit2014", citation: "Buchheit 2014", title: "Monitoring training status with HR measures: do all roads lead to Rome?", journal: "Front Physiol", doi: "10.3389/fphys.2014.00073", pmid: "24578692", kind: .review),
    Study(id: "saw2016", citation: "Saw et al. 2016", title: "Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures: a systematic review.", journal: "Br J Sports Med", doi: "10.1136/bjsports-2015-094758", pmid: "26423706", kind: .systematicReview),
    Study(id: "foster2001", citation: "Foster et al. 2001", title: "A new approach to monitoring exercise training.", journal: "J Strength Cond Res", doi: nil, pmid: "11708692", kind: .study),
    Study(id: "seiler2006", citation: "Seiler & Kjerland 2006", title: "Quantifying training intensity distribution in elite endurance athletes: is there evidence for an \"optimal\" distribution?", journal: "Scand J Med Sci Sports", doi: "10.1111/j.1600-0838.2004.00418.x", pmid: "16430681", kind: .study),
    Study(id: "esteveLanao2007", citation: "Esteve-Lanao et al. 2007", title: "Impact of training intensity distribution on performance in endurance athletes.", journal: "J Strength Cond Res", doi: "10.1519/R-19725.1", pmid: "17685689", kind: .trial),
    Study(id: "munoz2014", citation: "Muñoz et al. 2014", title: "Does polarized training improve performance in recreational runners?", journal: "Int J Sports Physiol Perform", doi: "10.1123/ijspp.2012-0350", pmid: "23752040", kind: .trial),
    Study(id: "rosenblat2025", citation: "Rosenblat et al. 2025", title: "Which Training Intensity Distribution Intervention will Produce the Greatest Improvements in Maximal Oxygen Uptake and Time-Trial Performance in Endurance Athletes?", journal: "Sports Med", doi: "10.1007/s40279-024-02149-3", pmid: "39888556", kind: .metaAnalysis),
    Study(id: "helgerud2007", citation: "Helgerud et al. 2007", title: "Aerobic high-intensity intervals improve VO2max more than moderate training.", journal: "Med Sci Sports Exerc", doi: "10.1249/mss.0b013e3180304570", pmid: "17414804", kind: .trial),
    Study(id: "nes2013", citation: "Nes et al. 2013", title: "Age-predicted maximal heart rate in healthy subjects: The HUNT fitness study.", journal: "Scand J Med Sci Sports", doi: "10.1111/j.1600-0838.2012.01445.x", pmid: "22376273", kind: .cohort),
    Study(id: "neudorfer2024", citation: "Neudorfer et al. 2024", title: "Validity of Four Consumer-Grade Optical Heart Rate Sensors for Assessing Volume and Intensity Distribution of Physical Activity.", journal: "Scand J Med Sci Sports", doi: "10.1111/sms.14756", pmid: "39508366", kind: .study),
    Study(id: "ronnestad2013", citation: "Rønnestad & Mujika 2013", title: "Optimizing strength training for running and cycling endurance performance: A review.", journal: "Scand J Med Sci Sports", doi: "10.1111/sms.12104", pmid: "23914932", kind: .review),
    Study(id: "denadai2017", citation: "Denadai et al. 2017", title: "Explosive Training and Heavy Weight Training are Effective for Improving Running Economy in Endurance Athletes: A Systematic Review and Meta-Analysis.", journal: "Sports Med", doi: "10.1007/s40279-016-0604-z", pmid: "27497600", kind: .metaAnalysis),
    Study(id: "blagrove2018", citation: "Blagrove et al. 2018", title: "Effects of Strength Training on the Physiological Determinants of Middle- and Long-Distance Running Performance: A Systematic Review.", journal: "Sports Med", doi: "10.1007/s40279-017-0835-7", pmid: "29249083", kind: .systematicReview),
    Study(id: "wilson2012", citation: "Wilson et al. 2012", title: "Concurrent training: a meta-analysis examining interference of aerobic and resistance exercises.", journal: "J Strength Cond Res", doi: "10.1519/JSC.0b013e31823a3e2d", pmid: "22002517", kind: .metaAnalysis),
    Study(id: "murlasits2017", citation: "Murlasits et al. 2017", title: "The physiological effects of concurrent strength and endurance training sequence: A systematic review and meta-analysis.", journal: "J Sports Sci", doi: "10.1080/02640414.2017.1364405", pmid: "28783467", kind: .metaAnalysis),
    Study(id: "huiberts2023", citation: "Huiberts et al. 2023", title: "Concurrent Strength and Endurance Training: A Systematic Review and Meta-Analysis on the Impact of Sex and Training Status.", journal: "Sports Med", doi: "10.1007/s40279-023-01943-9", pmid: "37847373", kind: .metaAnalysis),
    Study(id: "acsm2009", citation: "ACSM 2009", title: "American College of Sports Medicine position stand. Progression models in resistance training for healthy adults.", journal: "Med Sci Sports Exerc", doi: "10.1249/MSS.0b013e3181915670", pmid: "19204579", kind: .consensus),
    Study(id: "currier2026", citation: "Currier et al. 2026 (ACSM)", title: "American College of Sports Medicine Position Stand. Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews.", journal: "Med Sci Sports Exerc", doi: "10.1249/MSS.0000000000003897", pmid: "41843416", kind: .consensus),
    Study(id: "schoenfeld2017", citation: "Schoenfeld et al. 2017", title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass: A systematic review and meta-analysis.", journal: "J Sports Sci", doi: "10.1080/02640414.2016.1210197", pmid: "27433992", kind: .metaAnalysis),
    Study(id: "pelland2025", citation: "Pelland et al. 2025", title: "The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains.", journal: "Sports Med", doi: "10.1007/s40279-025-02344-w", pmid: "41343037", kind: .metaAnalysis),
    Study(id: "wang2023", citation: "Wang et al. 2023", title: "Effects of tapering on performance in endurance athletes: A systematic review and meta-analysis.", journal: "PLoS One", doi: "10.1371/journal.pone.0282838", pmid: "37163550", kind: .metaAnalysis),
    Study(id: "mifflin1990", citation: "Mifflin et al. 1990", title: "A new predictive equation for resting energy expenditure in healthy individuals.", journal: "Am J Clin Nutr", doi: "10.1093/ajcn/51.2.241", pmid: "2305711", kind: .study),
    Study(id: "thomas2016", citation: "Thomas et al. 2016 (ACSM/AND/DC)", title: "American College of Sports Medicine Joint Position Statement. Nutrition and Athletic Performance.", journal: "Med Sci Sports Exerc", doi: "10.1249/MSS.0000000000000852", pmid: "26891166", kind: .consensus),
    Study(id: "jaeger2017", citation: "Jäger et al. 2017 (ISSN)", title: "International Society of Sports Nutrition Position Stand: protein and exercise.", journal: "J Int Soc Sports Nutr", doi: "10.1186/s12970-017-0177-8", pmid: "28642676", kind: .consensus),
    Study(id: "mountjoy2023", citation: "Mountjoy et al. 2023 (IOC)", title: "2023 International Olympic Committee's (IOC) consensus statement on Relative Energy Deficiency in Sport (REDs).", journal: "Br J Sports Med", doi: "10.1136/bjsports-2023-106994", pmid: "37752011", kind: .consensus),
    Study(id: "watson2015", citation: "Watson et al. 2015 (AASM/SRS)", title: "Recommended Amount of Sleep for a Healthy Adult: A Joint Consensus Statement of the American Academy of Sleep Medicine and Sleep Research Society.", journal: "Sleep", doi: "10.5665/sleep.4716", pmid: "26039963", kind: .consensus),
    Study(id: "fullagar2015", citation: "Fullagar et al. 2015", title: "Sleep and athletic performance: the effects of sleep loss on exercise performance, and physiological and cognitive responses to exercise.", journal: "Sports Med", doi: "10.1007/s40279-014-0260-0", pmid: "25315456", kind: .review),
    Study(id: "walsh2021", citation: "Walsh et al. 2021", title: "Sleep and the athlete: narrative review and 2021 expert consensus recommendations.", journal: "Br J Sports Med", doi: "10.1136/bjsports-2020-102025", pmid: "33144349", kind: .consensus),
    Study(id: "wakayoshi1992", citation: "Wakayoshi et al. 1992", title: "A simple method for determining critical speed as swimming fatigue threshold in competitive swimming.", journal: "Int J Sports Med", doi: "10.1055/s-2007-1021282", pmid: "1521952", kind: .study),
    Study(id: "windred2024", citation: "Windred et al. 2024", title: "Sleep regularity is a stronger predictor of mortality risk than sleep duration: A prospective cohort study.", journal: "Sleep", doi: "10.1093/sleep/zsad253", pmid: "37738616", kind: .cohort),
  ]

  public static let studiesByID = Dictionary(uniqueKeysWithValues: studies.map { ($0.id, $0) })

  // swift-format-ignore
  public static let rules: [EvidenceRule] = [
    EvidenceRule(id: "recovery.hrv", title: "HRV im Wochenmittel", statement: "Maßgeblich für die Tagesform ist der 7-Tage-Schnitt der HRV relativ zur persönlichen Baseline, nicht die einzelne Nacht.", strength: .moderate, studyIDs: ["plews2012", "plews2013", "buchheit2014"]),
    EvidenceRule(id: "recovery.rhr", title: "Ruhepuls", statement: "Ein Ruhepuls deutlich über dem eigenen Mittel kann auf unvollständige Erholung hinweisen; die Schwelle von +5 Schlägen ist ein vorsichtiger Praxiswert.", strength: .practice, studyIDs: ["buchheit2014"]),
    EvidenceRule(id: "recovery.sleep", title: "Schlafdauer", statement: "Erwachsene brauchen regelmäßig mindestens 7 Stunden Schlaf; Schlafmangel verschlechtert Ausdauerleistung und Erholung.", strength: .strong, studyIDs: ["watson2015", "fullagar2015", "walsh2021"]),
    EvidenceRule(id: "recovery.subjective", title: "Befinden zählt", statement: "Subjektives Befinden reagiert empfindlicher auf Trainingsbelastung als viele objektive Marker und gehört in die Einordnung.", strength: .strong, studyIDs: ["saw2016"]),
    EvidenceRule(id: "sleep.regularity", title: "Regelmäßiger Schlaf", statement: "Regelmäßige Schlafzeiten sagen Gesundheit stärker voraus als die Schlafdauer allein.", strength: .moderate, studyIDs: ["windred2024", "walsh2021"]),
    EvidenceRule(id: "load.rpe", title: "Belastung per RPE", statement: "Das subjektive Anstrengungsempfinden je Einheit (Session-RPE) ist ein gültiges Maß für die Trainingsbelastung über Sportarten hinweg.", strength: .moderate, studyIDs: ["foster2001"]),
    EvidenceRule(id: "intensity.distribution", title: "Überwiegend locker", statement: "Ausdauersportler trainieren erfolgreich mit etwa 80 % lockerer Intensität und wenigen harten Einheiten; polarisierte und pyramidale Verteilungen sind ähnlich wirksam.", strength: .strong, studyIDs: ["seiler2006", "esteveLanao2007", "munoz2014", "rosenblat2025"]),
    EvidenceRule(id: "run.4x4", title: "4×4-Intervalle", statement: "4×4 Minuten bei 90–95 % der maximalen Herzfrequenz mit 3 Minuten Trabpause steigern die VO2max stärker als moderates Dauertraining gleicher Arbeit.", strength: .moderate, studyIDs: ["helgerud2007"]),
    EvidenceRule(id: "hr.threshold-zones", title: "Zonen an der Schwelle", statement: "Intensitätszonen werden besser an Schwellen als an Prozent der maximalen Herzfrequenz verankert; die Zonenbreiten nach Friel sind Praxiswerte.", strength: .moderate, studyIDs: ["esteveLanao2007", "seiler2006"]),
    EvidenceRule(id: "hr.max-formula", title: "Keine HFmax-Formel", statement: "Altersformeln für die maximale Herzfrequenz weichen im Einzelfall um rund 10 Schläge ab; gemessene Werte sind besser.", strength: .strong, studyIDs: ["nes2013"]),
    EvidenceRule(id: "hr.optical", title: "Optischer Puls", statement: "Optische Pulsmesser am Handgelenk unterschätzen die Zeit in hohen Intensitätszonen.", strength: .moderate, studyIDs: ["neudorfer2024"]),
    EvidenceRule(id: "strength.economy", title: "Kraft für Ausdauer", statement: "Schweres Krafttraining zwei- bis dreimal pro Woche verbessert Lauf- und Radökonomie, ohne Ausdauerwerte zu verschlechtern.", strength: .strong, studyIDs: ["ronnestad2013", "denadai2017", "blagrove2018"]),
    EvidenceRule(id: "strength.interference", title: "Interferenz ist klein", statement: "Ausdauer- und Krafttraining kombiniert bremst vor allem die Beinkraft etwas; bei trainierten Ausdauersportlern ist der VO2max-Nachteil gering.", strength: .strong, studyIDs: ["wilson2012", "murlasits2017", "huiberts2023"]),
    EvidenceRule(id: "gym.progression", title: "Progression", statement: "Steigt das Ziel bei den Wiederholungen um 1–2, wird die Last um 2–10 % erhöht (Doppelprogression).", strength: .strong, studyIDs: ["acsm2009", "currier2026"]),
    EvidenceRule(id: "gym.volume", title: "Sätze pro Woche", statement: "Mehr wöchentliche Sätze je Muskel bringen mehr Muskelzuwachs, mit abnehmendem Ertrag; für Kraft genügen schon wenige Sätze an zwei Tagen pro Woche.", strength: .strong, studyIDs: ["schoenfeld2017", "pelland2025", "currier2026"]),
    EvidenceRule(id: "swim.css", title: "CSS-Test", statement: "Die kritische Schwimmgeschwindigkeit aus zwei Maximalstrecken (400 m und 200 m) schätzt das Tempo, das lange ohne Erschöpfung gehalten werden kann.", strength: .moderate, studyIDs: ["wakayoshi1992"]),
    EvidenceRule(id: "taper", title: "Tapering", statement: "Vor dem Wettkampf den Umfang über bis zu drei Wochen um etwa 41–60 % senken, Intensität und Häufigkeit beibehalten.", strength: .strong, studyIDs: ["wang2023"]),
    EvidenceRule(id: "nutrition.energy", title: "Energiebedarf", statement: "Der Grundumsatz wird mit der Mifflin-St-Jeor-Formel geschätzt; der Tagesbedarf ergibt sich aus Alltag und Training.", strength: .moderate, studyIDs: ["mifflin1990", "thomas2016"]),
    EvidenceRule(id: "nutrition.carbs", title: "Kohlenhydrate nach Belastung", statement: "Der Kohlenhydratbedarf richtet sich nach der Trainingsbelastung des Tages (etwa 3 bis 10 g pro kg Körpergewicht).", strength: .strong, studyIDs: ["thomas2016"]),
    EvidenceRule(id: "nutrition.protein", title: "Protein", statement: "1,4–2,0 g Protein pro kg Körpergewicht und Tag, verteilt auf Portionen von etwa 0,25 g/kg alle 3–4 Stunden.", strength: .strong, studyIDs: ["jaeger2017", "thomas2016"]),
    EvidenceRule(id: "nutrition.reds", title: "Genug Energie", statement: "Dauerhaft zu wenig Energie im Verhältnis zum Training schadet Gesundheit und Leistung; eine Untergrenze schützt davor.", strength: .strong, studyIDs: ["mountjoy2023"]),
  ]

  public static let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })

  public static func rules(_ ids: [String]) -> [EvidenceRule] {
    ids.compactMap { rulesByID[$0] }
  }
}

extension Recommendation {
  /// Regeln hinter der Tagesampel.
  public var evidenceIDs: [String] { ["recovery.hrv", "recovery.rhr", "recovery.sleep", "recovery.subjective"] }
}
