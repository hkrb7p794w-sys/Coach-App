# KI-Modelle und Anbieter (Paket 3)

Stand: 01.11.2026. Ziel: möglichst gute Modelle ohne laufende Kosten, mit Datenschutz und austauschbar.

## Drei Kostenarten

„Open Source“ heißt nur, dass die **Modellgewichte** frei sind. Davon getrennt:

| | Was es heißt | Beispiel |
|---|---|---|
| Kostenlose Gewichte | Herunterladen und selbst betreiben erlaubt (Lizenz beachten) | Gemma 4, Qwen 3.x, Mistral Small, DeepSeek V4, gpt-oss |
| Kostenlose Nutzung | Ein Anbieter rechnet bis zu einem Kontingent nicht ab | Gemini (Free Tier), Groq (Free Tier), Workers AI (10.000 Neurons/Tag) |
| Infrastrukturkosten | Strom, Hardware, gemietete GPU – auch bei freien Gewichten | eigener PC mit Grafikkarte, Cloud-GPU |

## Modelle

Lizenzen laut Modellkarte auf Hugging Face (primäre Quelle), Speicherbedarf als grobe Schätzung für 4-Bit-Quantisierung
(Q4, rund 0,6 GB je Milliarde Parameter plus Kontext). Die Qualität bei strukturierten Daten ist eine Einschätzung
aus Modellgröße, JSON-Modus und Funktionsaufrufen – kein eigener Benchmark.

| Modell | Lizenz | Größe | Speicher Q4 | Strukturierte Daten | Hinweis |
|---|---|---|---|---|---|
| Gemma 4 26B A4B (Google) | Apache 2.0 | 26 Mrd., 4 Mrd. aktiv (MoE) | ca. 16 GB | gut, JSON und Funktionsaufrufe, Bilder | schnell, da nur 4 Mrd. aktiv; bei Workers AI kostenlos nutzbar |
| Qwen 3.8 27B (Alibaba) | Apache 2.0 | 27 Mrd. | ca. 17 GB | sehr gut | bei Workers AI deutlich teurer (3,20 $/Mio. Ausgabe-Tokens) |
| Qwen 3 30B A3B | Apache 2.0 | 30 Mrd., 3 Mrd. aktiv | ca. 18 GB | gut | sehr günstig, läuft auch auf CPU passabel |
| DeepSeek V4 Flash | MIT | 291 Mrd. (MoE) | ca. 170 GB | sehr gut | nicht für Heim-Hardware; gehostet bei Workers AI (0,30/1,20 $) |
| Llama 4 Scout (Meta) | Llama-Lizenz (eigene Bedingungen, Zugang auf Anfrage) | 109 Mrd., 17 Mrd. aktiv | ca. 60 GB | gut | Lizenz mit Nutzungsbedingungen und Namensnennung; bei Groq und Workers AI |
| Mistral Small 3.2 24B | Apache 2.0 | 24 Mrd. | ca. 14 GB | gut, Funktionsaufrufe | europäischer Anbieter, gut auf Deutsch |
| gpt-oss-120b / 20b (OpenAI) | Apache 2.0 | 117 bzw. 21 Mrd. | ca. 63 bzw. 14 GB | sehr gut bzw. gut | bei Groq im Free Tier |

Geschwindigkeit: MoE-Modelle (Gemma 4 A4B, Qwen 3 A3B) rechnen nur mit den aktiven Parametern und antworten auf
derselben Hardware deutlich schneller als dichte Modelle gleicher Größe. Gehostet (Groq, Workers AI) sind alle
genannten Modelle für die App schnell genug (Sekunden).

## Anbieter

| Anbieter | Kosten | Datenschutz | In der App |
|---|---|---|---|
| Google Gemini (Free Tier) | 0 € im Kontingent | Im kostenlosen Kontingent darf Google Eingaben zur Verbesserung nutzen (Gemini API Additional Terms) | bisher Standard; Datenschutz „reduziert“ schickt keine Rohwerte |
| Cloudflare Workers AI | 10.000 Neurons/Tag frei; Gemma 4: 9.091 Neurons je Mio. Eingabe-, 27.273 je Mio. Ausgabe-Tokens → rund 150 Anfragen/Tag (4.000 + 1.000 Tokens) | keine Speicherung, kein Training (Cloudflare „Data usage“) | **neu**, läuft im selben Worker ohne eigenen Key |
| Groq (Free Tier) | 0 € mit Tageslimits je Modell | eigene Richtlinien, kein Training laut Anbieter | wie bisher Ausweichstufe |
| Eigener Server (Ollama, LM Studio, llama.cpp, vLLM) | nur Strom und Hardware | Daten bleiben bei dir | **neu**, OpenAI-kompatibel, per Tunnel erreichbar |
| OpenRouter, Mistral, DeepSeek-API | je Anbieter (teils freie Modelle mit Limits) | je Anbieter, freie Endpunkte teils mit Protokollierung | über „eigener Server“ (gleiche Schnittstelle) möglich |
| Apple Foundation Models (auf dem iPhone) | 0 € | bleibt auf dem Gerät | geprüft, nicht umgesetzt (siehe unten) |

Quellen: [Workers AI Pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/),
[Workers AI Data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/),
[Gemma 4 26B A4B](https://hf.co/google/gemma-4-26B-A4B-it), [Qwen 3.8 27B](https://hf.co/Qwen/Qwen3.8-27B),
[Qwen 3 30B A3B](https://hf.co/Qwen/Qwen3-30B-A3B), [DeepSeek V4 Flash](https://hf.co/deepseek-ai/DeepSeek-V4-Flash),
[Llama 4 Scout](https://hf.co/meta-llama/Llama-4-Scout-17B-16E-Instruct),
[Mistral Small 3.2](https://hf.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506),
[gpt-oss-120b](https://hf.co/openai/gpt-oss-120b). Groq-Limits laut Drittquellen (z. B.
[OpenRouter-Vergleich](https://openrouter.ai/blog/tutorials/free-llm-apis-compared/)); maßgeblich ist
console.groq.com/settings/limits.

## Selbst hosten: was es kostet

- **Hardware:** Für Gemma 4 26B A4B, Qwen 3 30B A3B oder Mistral Small reichen 16–24 GB Grafikspeicher (oder ein
  Mac mit 32 GB). Kleinere Modelle (7–14 Mrd.) laufen mit 8–12 GB, sind bei Trainings- und Ernährungsanalysen aber
  spürbar schwächer.
- **Strom:** Eine Antwort braucht auf einer Grafikkarte mit 300 W etwa 10–30 Sekunden, also rund 1–3 Wh – unter
  0,1 Cent. Teuer wird der Dauerbetrieb: Ein PC, der nur dafür rund um die Uhr läuft (60–100 W im Leerlauf), kostet
  bei 0,35 €/kWh etwa 15–25 € im Monat.
- **Erreichbarkeit:** Der Worker läuft bei Cloudflare und braucht eine https-Adresse: z. B. Cloudflare Tunnel
  (kostenlos) vor Ollama. Ist der PC aus, weicht der Worker auf die anderen Anbieter aus.
- **Gemietete GPU:** 0,50–2 € pro Stunde, dauerhaft also 350–1.400 € im Monat – für eine Person nicht sinnvoll.

## Auf dem iPhone (Apple Foundation Models)

Kostenlos und privat, aber: nur iOS 26 auf Geräten mit Apple Intelligence, ein kleines Modell (rund 3 Mrd.
Parameter) mit kurzem Kontext, und die Prompts samt Prüfungen liegen heute im Worker. Eine Umsetzung bräuchte die
Prompts doppelt (App und Worker). Deshalb vorerst nicht umgesetzt; die Anbieter-Schnittstelle lässt es später zu.

## Architektur

- **Worker:** `worker/src/providers.ts` ist das Register. Jeder Anbieter hat dieselbe Schnittstelle (`run`), dazu
  Modell, Bild-Fähigkeit, ob Eingaben zum Training genutzt werden, und Listenpreise. Neue Anbieter oder Modelle
  kommen dort dazu – Aufgaben, Prompts und Prüfungen (`tasks.ts`, `grounding.ts`) bleiben unverändert.
- **Reihenfolge:** `AI_PROVIDER_ORDER` (Worker-Variable) oder Standard Gemini → Workers AI → Groq → eigener Server.
  Die App schickt eine Vorliebe (`auto`, `privat` oder ein Anbieter). „Datenschutz zuerst“ schließt Anbieter aus, die
  Eingaben zum Training nutzen – auch beim Ausweichen.
- **Einrichtung:** Workers AI über das Binding `AI` in `wrangler.jsonc` (Modell `WORKERS_AI_MODEL`). Eigener Server
  über `OPENAI_COMPAT_URL` (https), `OPENAI_COMPAT_MODEL` und optional das Secret `OPENAI_COMPAT_KEY`.
- **App:** `AIClient` prüft jede Anfrage gegen die KI-Stufe (`AIPolicy`) und protokolliert Anbieter, Modell, Tokens,
  Dauer und Listenpreis ohne Inhalte (`AIUsageLog`, Einstellungen › KI › Anbieter und Nutzung).

## Empfehlung

1. **Datenschutz zuerst** in den Einstellungen wählen, wenn Rohwerte (Ruhepuls, HRV, Schlaf) an die KI dürfen sollen:
   Workers AI mit Gemma 4 ist kostenlos, speichert nichts und reicht für Notizen, Analysen und Chat.
2. **Automatisch** behalten, wenn Fotos von Mahlzeiten möglichst genau erkannt werden sollen (Gemini ist dort am
   stärksten) – mit Datenschutz „reduziert“.
3. Eigener Server nur, wenn ein passender PC ohnehin läuft.
