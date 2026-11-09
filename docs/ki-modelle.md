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

## Aktualisierung 08.11.2026 (Paket 11)

**Preise Workers AI** laut [Cloudflare](https://developers.cloudflare.com/workers-ai/platform/pricing/), US-Dollar je
Million Tokens (Eingabe/Ausgabe). Kostenlos sind 10.000 Neurons am Tag.

| Modell | Eingabe | Ausgabe | Hinweis |
|---|---|---|---|
| Gemma 4 26B A4B | 0,10 | 0,30 | heute im Einsatz |
| Qwen 3 30B A3B | 0,051 | 0,335 | günstigste Alternative mit guter Größe |
| GLM 4.7 Flash | 0,06 | 0,40 | neu in der Liste |
| Mistral Small 3.1 24B | 0,351 | 0,555 | |
| gpt-oss-120b | 0,35 | 0,75 | |
| Llama 4 Scout | 0,27 | 0,85 | |
| Qwen 3.8 27B | 0,45 | 3,20 | |
| DeepSeek V4.1 Flash | 0,30 | 1,20 | nur mit bezahltem Plan |
| GLM 5.3 Flash | 0,15 | 0,50 | nur mit bezahltem Plan |
| Kimi K2.5 | 0,60 | 3,00 | |

**Neuere offene Modelle** laut Ranglisten von Oktober 2026: Kimi K3, GLM-5.2, DeepSeek V4, Qwen 3.6, Mistral Small 4.
Die Spitzenwerte sind teils Herstellerangaben, und die Quellen widersprechen sich beim ersten Platz. Die großen Modelle
(Kimi K3 mit 2,8 Billionen Parametern) kommen für Heim-Hardware nicht infrage.

**Was nicht belegt ist:** Zu Trainings- und Ernährungsqualität, langen Gesprächen, JSON-Zuverlässigkeit und deutschen
Antworten habe ich keine belastbaren Vergleiche gefunden. Auch die Gemini-Limits im kostenlosen Kontingent nennen
Drittquellen widersprüchlich (von 20 bis 250 Anfragen am Tag), maßgeblich ist die Google-Konsole. Gemessen werden kann
das nur am eigenen Fall: Die Chat-Auswertung (`.github/scripts/chat-eval.mjs`, Workflow „Worker-Smoke“) und der
Rezept-Smoke laufen gegen jeden eingerichteten Anbieter.

**Empfehlung je Aufgabe**

| Aufgabe | Modell | Begründung |
|---|---|---|
| Berechnungen (Ziele, Ampel, Restwerte, Volumen) | keins, Regeln im Code | „Regeln entscheiden, KI formuliert“ |
| Chat, Notizen, Analysen | Gemini Flash, Ausweichen auf Gemma 4 | live gemessen, siehe Bericht Paket 12 |
| Rezeptideen, Kochplan | Gemini Flash mit wenig Denken, in Teilen zu 2 Tagen | gemessen in Paket 9 |
| Foto-Erkennung | Gemini Flash | stärkste Bilderkennung im freien Kontingent |
| Datenschutz „privat“ | Workers AI mit Gemma 4 | speichert nichts, kein Training |

**Modulare Anbieter:** Die Architektur reicht aus. Ein neues Modell ist ein Eintrag in `providers.ts` oder eine
Worker-Variable, jeder OpenAI-kompatible Dienst läuft über „eigener Server“. Ein Wechsel lohnt sich erst, wenn ein Modell
in der Auswertung messbar besser abschneidet.

Weitere Quellen (Drittquellen): [Morph, Oktober 2026](https://www.morphllm.com/open-source-llm),
[Morph, Gemini-Preise](https://www.morphllm.com/gemini-api-pricing), [Apidog](https://apidog.com/blog/gemini-api-free-tier/),
[Wavect](https://wavect.io/blog/open-weight-llm-comparison-2026.md).

## Reihenfolge je Aufgabe (09.11.2026)

Auftrag des Nutzers: weitere kostenlose Anbieter (Cerebras, Groq, Workers AI, Mistral) und je Aufgabe der stärkste
zuerst, die übrigen als Reserve, wenn ein Kontingent aufgebraucht ist. Umsetzung in `worker/src/providers.ts`
(`TASK_ROUTES`), änderbar ohne Code über die Worker-Variable `AI_TASK_ORDER` (JSON, z. B.
`{"weekly_recipes": "gemini,cerebras"}`). Nicht genannte Anbieter folgen danach; Anbieter ohne Key werden übersprungen.

| Aufgaben | Reihenfolge | Begründung |
|---|---|---|
| `meal_analyze`, `meal_amend`, `nutrition_label` (Fotos) | Gemini → GitHub Models → Mistral → Groq (Llama 4 Scout) → Workers AI | Gemini erkennt Bilder am besten, GPT-4.1 als zweites starkes Bildmodell; Cerebras hat keine Bild-Eingabe |
| `weekly_recipes`, `cook_plan`, `gym_plan`, `meal_now` (lange JSON-Antworten) | Cerebras → Gemini → GitHub Models → Groq → Workers AI → Mistral | gpt-oss-120b stark bei JSON, großes Kontingent; schont Gemini. GitHub Models nur bis 4.000 Ausgabe-Tokens |
| `coach_chat`, `ai_insights`, `daily_note`, `personal_note`, `nutrition_review` | Gemini → Cerebras → GitHub Models → Mistral → Groq → Workers AI | Gesprächsqualität und Deutsch |
| `gym_hints` | Groq → Cerebras → Gemini → GitHub Models → Workers AI → Mistral | kurz, Geschwindigkeit zählt |
| übrige (`ping`) | Gemini → Cerebras → Groq → GitHub Models → Workers AI → Mistral → eigener Server | Standard |

- **GitHub Models** (ergänzt am 09.11.2026, weil Cerebras eine Kreditkarte verlangt und Groq/Mistral sich beim Nutzer
  nicht einrichten ließen): Fine-grained Token mit „Models: Read-only“ (`GH_MODELS_TOKEN`), Modell `openai/gpt-4.1`
  (`GITHUB_MODEL`), Endpunkt `https://models.github.ai/inference`. Kostenlose Stufe mit knappen Tages- und
  Anfragelimits (Größenordnung 50–150 Anfragen am Tag je nach Modell, maßgeblich ist die GitHub-Doku) und höchstens
  4.000 Ausgabe-Tokens – daher Reserve, nicht erste Wahl. Laut GitHub keine Nutzung der Eingaben zum Training.
- **Datenschutz zuerst** (`privat`) schließt Gemini und Mistral (kostenlose Stufe „Experiment“, Eingaben dürfen zum
  Training genutzt werden) auch beim Ausweichen aus.
- Eine ausdrückliche Anbieterwahl in der App steht vor der Aufgaben-Reihenfolge.
- **Nicht gemessen:** Ob gpt-oss-120b bei Cerebras die Rezept- und Planprüfungen (`grounding.ts`) so zuverlässig
  besteht wie Gemini, ist nicht belegt. Besteht eine Antwort die Prüfung nicht, kommt automatisch der nächste Anbieter
  dran. Messbar mit dem Workflow „Worker-Smoke“, sobald die Keys gesetzt sind.
- Modelle: Cerebras `gpt-oss-120b` (`CEREBRAS_MODEL`, mit `reasoning_effort` niedrig bei großen JSON-Antworten),
  Mistral `mistral-medium-latest` (`MISTRAL_MODEL`, für Bilder optional `MISTRAL_VISION_MODEL`).
- **DeepSeek** bewusst nicht aufgenommen: offizielle API kostenpflichtig mit Servern in China (Datenschutz bei
  Gesundheitsdaten), keine Bilder, kostenlose Varianten nur unzuverlässig über OpenRouter; gpt-oss-120b bei Cerebras
  und Groq deckt dieselben Stärken ab.

Quellen: [GitHub Models – Prototyping und Limits](https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models),
[Cerebras Inference Docs](https://inference-docs.cerebras.ai/), [Mistral Docs](https://docs.mistral.ai/),
[Groq Rate Limits](https://console.groq.com/docs/rate-limits). Kontingente ändern sich; maßgeblich ist die Konsole des
jeweiligen Anbieters.

## Empfehlung

1. **Datenschutz zuerst** in den Einstellungen wählen, wenn Rohwerte (Ruhepuls, HRV, Schlaf) an die KI dürfen sollen:
   Workers AI mit Gemma 4 ist kostenlos, speichert nichts und reicht für Notizen, Analysen und Chat.
2. **Automatisch** behalten, wenn Fotos von Mahlzeiten möglichst genau erkannt werden sollen (Gemini ist dort am
   stärksten) – mit Datenschutz „reduziert“.
3. Eigener Server nur, wenn ein passender PC ohnehin läuft.
