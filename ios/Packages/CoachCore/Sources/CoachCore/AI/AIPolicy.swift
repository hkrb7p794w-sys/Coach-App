import Foundation

/// Wie viel KI die App nutzen darf. Regeln, eigene Auswertungen, Importe und der Export funktionieren in jeder
/// Stufe – die KI formuliert nur, sie entscheidet nichts.
public enum AIMode: String, Codable, CaseIterable, Sendable {
  /// Alles, auch automatische Notizen und Hinweise beim Öffnen.
  case full = "voll"
  /// Nur, wenn ausdrücklich angetippt (Analyse starten, Chat, Mahlzeit auswerten …).
  case onRequest = "auf_anfrage"
  /// Keine KI-Empfehlungen; die KI hilft nur bei der Datenerfassung (Mahlzeit, Etikett), auf Anfrage.
  case captureOnly = "nur_erfassung"
  /// Keine KI-Aufrufe.
  case off = "aus"

  public var label: String {
    switch self {
    case .full: "Vollständig"
    case .onRequest: "Nur auf Anfrage"
    case .captureOnly: "Keine KI-Empfehlungen"
    case .off: "Aus"
    }
  }

  public var detail: String {
    switch self {
    case .full: "Notizen, Hinweise und Analysen kommen auch automatisch, z. B. beim Öffnen von „Heute“."
    case .onRequest: "Die KI arbeitet nur, wenn du etwas antippst. Bis dahin stehen die Hinweise der Regeln."
    case .captureOnly:
      "Keine Empfehlungen, Notizen oder Chat von der KI. Sie liest nur Mahlzeiten und Etiketten aus, wenn du "
        + "darum bittest. Auswertungen der App und der Export bleiben."
    case .off: "Keine Anfrage an eine KI. Alle Regeln, Auswertungen, Importe und der Export funktionieren weiter."
    }
  }
}

/// Wofür eine Worker-Aufgabe die KI nutzt.
public enum AITaskKind: String, Codable, Sendable {
  /// Daten erfassen: Mahlzeit zerlegen, Etikett ablesen.
  case capture
  /// Empfehlungen, Notizen, Analysen, Chat.
  case recommendation
  /// Pläne und Rezepte vorschlagen.
  case planning
  /// Verbindungstest ohne persönliche Daten.
  case system
}

/// Wer eine Anfrage auslöst.
public enum AITrigger: String, Codable, Sendable {
  case automatic
  case user
}

/// Zentrale Regel, ob eine KI-Anfrage erlaubt ist – gilt für alle Aufgaben im `AIClient`.
public enum AIPolicy {
  public static func kind(of task: String) -> AITaskKind {
    switch task {
    case "meal_analyze", "meal_amend", "nutrition_label": .capture
    case "gym_plan", "weekly_recipes", "meal_now", "cook_plan": .planning
    case "ping": .system
    default: .recommendation
    }
  }

  public static func allows(_ mode: AIMode, task: String, trigger: AITrigger) -> Bool {
    let kind = kind(of: task)
    if kind == .system { return trigger == .user }
    switch mode {
    case .full: return true
    case .onRequest: return trigger == .user
    case .captureOnly: return trigger == .user && kind == .capture
    case .off: return false
    }
  }

  /// Hinweis, wenn die Einstellung eine Anfrage verhindert.
  public static func blockedMessage(_ mode: AIMode) -> String {
    switch mode {
    case .full, .onRequest: "Die KI läuft in dieser Einstellung nur auf Anfrage."
    case .captureOnly: "KI-Empfehlungen sind ausgeschaltet (Einstellungen › KI)."
    case .off: "Die KI ist ausgeschaltet (Einstellungen › KI)."
    }
  }
}

/// Bevorzugter KI-Anbieter. Welche eingerichtet sind, weiß der Worker; er weicht bei Ausfall auf die übrigen aus.
public enum AIProviderChoice: String, Codable, CaseIterable, Sendable {
  case auto
  /// Nur Anbieter, die Eingaben nicht zum Training nutzen (kein kostenloses Gemini).
  case privat
  case workersAI = "workers_ai"
  case gemini
  case cerebras
  case groq
  case mistral
  case ownServer = "openai_compat"

  public var label: String {
    switch self {
    case .auto: "Automatisch"
    case .privat: "Datenschutz zuerst"
    case .workersAI: "Cloudflare Workers AI"
    case .gemini: "Google Gemini"
    case .cerebras: "Cerebras"
    case .groq: "Groq"
    case .mistral: "Mistral"
    case .ownServer: "Eigener Server"
    }
  }

  public var detail: String {
    switch self {
    case .auto:
      "Je Aufgabe der passende Anbieter: Fotos an Gemini, Pläne und Rezepte an Cerebras, Gespräche an Gemini. "
        + "Ist ein Kontingent aufgebraucht, übernimmt der nächste."
    case .privat:
      "Nur Anbieter ohne Training mit deinen Eingaben: eigener Server, Cerebras, Groq, Workers AI. "
        + "Nie das kostenlose Gemini oder Mistral."
    case .workersAI:
      "Offene Modelle (Gemma 4) bei Cloudflare. 10.000 Neurons pro Tag frei (rund 150 Anfragen), keine Speicherung."
    case .gemini: "Stark bei Fotos und langen Texten. Im kostenlosen Kontingent darf Google Eingaben auswerten."
    case .cerebras:
      "Sehr schnell, GPT-OSS 120B, großes kostenloses Tageskontingent. Ohne Fotos. Laut Anbieter kein Training."
    case .groq: "Sehr schnell, Llama und GPT-OSS. Kostenloses Kontingent mit Tageslimits."
    case .mistral:
      "Europäischer Anbieter, sehr gutes Deutsch, auch Fotos. "
        + "In der kostenlosen Stufe darf Mistral Eingaben auswerten."
    case .ownServer: "Eigenes Modell (z. B. Ollama auf dem PC) – nur, wenn im Worker eingerichtet. Ohne Fotos."
    }
  }
}

/// KI-Einstellungen der App.
public struct AISettings: Codable, Equatable, Hashable, Sendable {
  public var mode: AIMode = .full
  public var provider: AIProviderChoice = .auto

  public init(mode: AIMode = .full, provider: AIProviderChoice = .auto) {
    self.mode = mode
    self.provider = provider
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = (try? container.decode(AIMode.self, forKey: .mode)) ?? .full
    provider = (try? container.decode(AIProviderChoice.self, forKey: .provider)) ?? .auto
  }
}
