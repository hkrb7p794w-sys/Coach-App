package io.github.hkrb7p794w.gym.core

/** Ein Lebensmittel aus dem Bundeslebensmittelschlüssel mit Nährwerten je 100 g. */
data class BlsFood(val code: String, val name: String, val per100g: NutrientMap) {
    /** Gerichte und Rezepte (Codes X und Y) statt einzelner Lebensmittel. */
    val isDish: Boolean get() = code.startsWith("X") || code.startsWith("Y")

    fun item(grams: Double = 100.0) =
        MealItem(name = name, grams = grams, source = FoodSource.BLS, per100g = per100g, blsCode = code, isDrink = Bls.isDrink(this))
}

/**
 * Bundeslebensmittelschlüssel 4.0 (Max Rubner-Institut), offline in der App (`assets/bls.tsv`, gleiche Datei wie
 * in CoachCore). Port von `BLS` in CoachCore: dieselbe Suche und dieselben Regeln für die Zuordnung von
 * KI-Suchbegriffen („Regeln entscheiden, KI formuliert“).
 */
class Bls(val foods: List<BlsFood>) {
    internal data class Entry(val tokens: List<String>, val inParens: List<Boolean>, val joined: String)

    private val entries: List<Entry> = foods.map { food ->
        val words = Tokens.words(food.name)
        val tokens = words.map { it.text }
        Entry(tokens, words.map { it.inParens }, tokens.joinToString(""))
    }
    private val byCode: Map<String, Int> = foods.withIndex().associate { it.value.code to it.index }

    fun food(code: String): BlsFood? = byCode[code]?.let { foods[it] }

    /** Freie Suche: alle Wörter müssen vorkommen (Wortanfang), kurze Namen zuerst. */
    fun search(query: String, limit: Int = 20): List<BlsFood> {
        val words = Tokens.words(query).map { it.text }.filter { it !in Tokens.stopwords }
        if (words.isEmpty() || words.joinToString("").length < 2) return emptyList()
        return entries.indices.mapNotNull { index ->
            val entry = entries[index]
            val all = words.all { word -> entry.tokens.any { it.startsWith(word) } || entry.joined.contains(word) }
            if (!all) return@mapNotNull null
            val head = entry.tokens.firstOrNull()?.let { Tokens.stem(it) == Tokens.stem(words[0]) } ?: false
            index to (if (head) 0 else 100) + (if (foods[index].isDish) 20 else 0) + entry.tokens.size
        }.sortedWith(compareBy<Pair<Int, Int>> { it.second }.thenBy { foods[it.first].name.length })
            .take(limit).map { foods[it.first] }
    }

    /** Bestes Lebensmittel zu einem Suchbegriff der KI oder `null`, wenn keins sicher genug passt. */
    fun match(term: String): BlsFood? {
        var words = Tokens.words(term).map { it.text }.filter { it !in Tokens.stopwords }
        val first = words.firstOrNull()
        if (first != null) Tokens.aliases[first]?.let { alias -> words = alias + words.drop(1) }
        val headWord = words.firstOrNull()?.takeIf { it.length >= 2 } ?: return null
        var bestIndex = -1
        var bestScore = 0
        for (index in entries.indices) {
            val entry = entries[index]
            val used = Tokens.head(headWord, entry)?.toMutableSet() ?: continue
            var matched = true
            for (word in words.drop(1)) {
                val hit = Tokens.find(word, entry.tokens, used)
                if (hit == null) {
                    matched = false
                    break
                }
                used.addAll(hit)
            }
            if (!matched) continue
            val extras = Tokens.extras(entry, used, words.size == 1) ?: continue
            val fillers = entry.tokens.size - used.size - extras
            val score = extras * 10 + fillers + if (foods[index].isDish) 5 else 0
            if (bestIndex >= 0 && (score > bestScore || (score == bestScore && foods[index].name.length >= foods[bestIndex].name.length))) continue
            bestIndex = index
            bestScore = score
        }
        return if (bestIndex >= 0) foods[bestIndex] else null
    }

    /** BLS-Werte übernehmen; was im BLS fehlt, bleibt aus der alten Quelle (außer sie war schon BLS). */
    fun apply(food: BlsFood, item: MealItem): MealItem {
        val base = if (item.source == FoodSource.BLS) emptyMap() else item.per100g
        return item.copy(per100g = base + food.per100g, source = FoodSource.BLS, blsCode = food.code)
    }

    /** KI-Positionen mit passendem BLS-Lebensmittel bekommen dessen Nährwerte. */
    fun enrich(item: MealItem): MealItem {
        if (item.source != FoodSource.AI) return item
        val term = listOfNotNull(item.searchTerm, item.name).firstOrNull { it.isNotEmpty() } ?: item.name
        val food = match(term) ?: (if (term == item.name) null else match(item.name)) ?: return item
        return apply(food, item)
    }

    companion object {
        const val ATTRIBUTION = "Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0. Karlsruhe"

        fun isDrink(food: BlsFood): Boolean =
            food.code.take(1) in setOf("N", "P") || food.name.contains("Getränk") || food.name.contains("drink") || food.name.endsWith("saft")

        /** Kommentarzeilen, Kopfzeile mit Nährstoff-Schlüsseln, dann eine Zeile je Lebensmittel. */
        fun parse(text: String): Bls {
            val lines = text.split("\n").filter { it.isNotEmpty() && !it.startsWith("#") }.toMutableList()
            if (lines.isEmpty()) return Bls(emptyList())
            val header = lines.removeAt(0).split("\t")
            val keys = header.drop(2).map { Nutrient.of(it)?.key }
            val foods = lines.mapNotNull { line ->
                val fields = line.split("\t")
                if (fields.size < 2) return@mapNotNull null
                val values = mutableMapOf<String, Double>()
                keys.forEachIndexed { offset, key ->
                    val value = fields.getOrNull(offset + 2)?.toDoubleOrNull()
                    if (key != null && value != null) values[key] = value
                }
                BlsFood(fields[0], fields[1], values)
            }
            return Bls(foods)
        }
    }
}

/** Wortzerlegung für BLS-Namen und Suchbegriffe (Port von `Tokens` in CoachCore). */
internal object Tokens {
    data class Word(val text: String, val inParens: Boolean = false)

    const val ALTERNATIVE = "/"

    val stopwords = setOf("mit", "und", "der", "die", "das", "von", "vom", "zum", "zur", "ca")

    private val fillers = setOf(
        "roh", "frisch", "pasteurisiert", "mind", "max", "fett", "i", "tr", "bis", "getraenk", "ungesuesst", "natur",
        "zubereitet", "verzehrfertig", "suess", "reif", "ganz", "geschaelt", "geroestet", "mild", "gesaeuert",
    )

    private val markers = setOf(
        "glutenfrei", "laktosefrei", "kohlenhydratreduziert", "energiereduziert", "riegel", "misch", "einlauf",
        "suppeneinlage", "pulver", "instantpulver", "getrocknet", "konserve", "angereichert", "trockenprodukt",
        "gesalzen", "gesuesst", "alkoholfrei", "entkoffeiniert", "koffeinreduziert",
    )

    val aliases = mapOf(
        "ei" to listOf("huehnerei"), "eier" to listOf("huehnerei"), "nudeln" to listOf("teigwaren", "eifrei"),
        "spaghetti" to listOf("teigwaren", "eifrei"), "pasta" to listOf("teigwaren", "eifrei"), "brokkoli" to listOf("broccoli"),
        "ketchup" to listOf("tomatenketchup"),
    )

    fun isFiller(token: String): Boolean = token == "mit" || token in fillers || token.all { it.isDigit() || it == '.' }

    fun words(text: String): List<Word> {
        val characters = FoodSearch.normalized(text).toCharArray()
        val words = mutableListOf<Word>()
        val current = StringBuilder()
        var depth = 0
        fun flush() {
            if (current.isNotEmpty()) words.add(Word(current.toString(), depth > 0))
            current.setLength(0)
        }
        for ((index, character) in characters.withIndex()) {
            if (character == ',' && index > 0 && index + 1 < characters.size && characters[index - 1].isDigit() && characters[index + 1].isDigit()) {
                current.append('.')
                continue
            }
            if (character.isLetter() || character.isDigit()) {
                current.append(character)
                continue
            }
            flush()
            if (character == '/' && depth == 0 && words.size == 1) words.add(Word(ALTERNATIVE))
            if (character == '(') depth += 1
            if (character == ')') depth = maxOf(0, depth - 1)
        }
        flush()
        return words
    }

    /** Einfache Grundform für Mehrzahl und Beugung. */
    fun stem(word: String): String {
        var result = word.replace("ae", "a").replace("oe", "o").replace("ue", "u")
        if (result.length > 4) {
            listOf("en", "n", "e").firstOrNull { result.endsWith(it) }?.let { result = result.dropLast(it.length) }
        }
        if (result.length > 4 && result.endsWith("s") && !result.endsWith("ss")) result = result.dropLast(1)
        return result
    }

    fun matchLength(word: String, tokens: List<String>, start: Int, exact: Boolean): Int? {
        if (start >= tokens.size) return null
        val target = stem(word)
        if (stem(tokens[start]) == target || (!exact && word.length >= 4 && tokens[start].startsWith(word))) return 1
        var joined = tokens[start]
        for (end in (start + 1) until minOf(start + 3, tokens.size)) {
            if (tokens[end] == ALTERNATIVE) continue
            joined += tokens[end]
            if (stem(joined) == target) return end - start + 1
        }
        return null
    }

    fun head(word: String, entry: Bls.Entry): Set<Int>? {
        val tokens = entry.tokens
        val hasAlternative = tokens.size > 2 && tokens[1] == ALTERNATIVE
        matchLength(word, tokens, 0, exact = true)?.let { length ->
            return (0 until length).toSet() + (if (hasAlternative) setOf(1, 2) else emptySet())
        }
        if (hasAlternative) {
            matchLength(word, tokens, 2, exact = true)?.let { length -> return (0 until 2 + length).toSet() }
        }
        return null
    }

    fun find(word: String, tokens: List<String>, used: Set<Int>): Set<Int>? {
        for (start in tokens.indices) {
            if (start in used) continue
            val length = matchLength(word, tokens, start, exact = false) ?: continue
            val range = (start until start + length).toSet()
            if (range.none { it in used }) return range
        }
        return null
    }

    fun extras(entry: Bls.Entry, used: Set<Int>, singleWord: Boolean): Int? {
        val rest = entry.tokens.indices.filter { it !in used }
        if (rest.any { entry.tokens[it] in markers }) return null
        val with = rest.firstOrNull { entry.tokens[it] == "mit" && !entry.inParens[it] }
        if (with != null && rest.any { it > with && !entry.inParens[it] && !isFiller(entry.tokens[it]) }) return null
        val plain = rest.count { !entry.inParens[it] && !isFiller(entry.tokens[it]) }
        val inParens = rest.count { entry.inParens[it] && !isFiller(entry.tokens[it]) }
        if (singleWord && plain + inParens > 0) return null
        if (plain > 1 || plain + inParens > 2) return null
        return plain + inParens
    }
}
