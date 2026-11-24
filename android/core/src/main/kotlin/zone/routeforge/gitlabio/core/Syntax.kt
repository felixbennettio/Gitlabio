package zone.routeforge.gitlabio.core

enum class TokenKind { KEYWORD, TYPE, STRING, NUMBER, COMMENT, ANNOTATION, FUNCTION, PROPERTY, TAG }

/** [start] and [end] are offsets into the whole highlighted text. */
data class SyntaxToken(val start: Int, val end: Int, val kind: TokenKind)

data class Language(
    val name: String,
    val keywords: Set<String> = emptySet(),
    val types: Set<String> = emptySet(),
    val lineComments: List<String> = emptyList(),
    val blockComment: Pair<String, String>? = null,
    val quotes: String = "\"'",
    val multilineQuotes: String = "",
    val tripleQuotes: Boolean = false,
    val annotation: Char? = null,
    /** Identifiers starting with an uppercase letter are treated as type names. */
    val capitalizedTypes: Boolean = false,
    /** `key:` / `"key":` are object keys (YAML, JSON, TOML…). */
    val keys: Boolean = false,
    val markup: Boolean = false,
    val headings: Boolean = false,
    val ignoreCase: Boolean = false,
)

/**
 * A small, fast lexer that recognizes comments, strings, numbers, keywords and type names for common
 * languages. It is deliberately approximate: the goal is readable code on a phone, not a parser.
 */
object Syntax {
    private fun words(text: String) = text.split(' ').filter { it.isNotEmpty() }.toSet()

    private val cFamilyTypes = words("int long short char float double void bool boolean byte unsigned signed size_t string String")

    val kotlin = Language("Kotlin", words("package import class interface object fun val var if else when for while do return break continue try catch finally throw is as in out by get set init constructor companion data sealed enum open abstract override private protected public internal inline reified suspend operator infix tailrec lateinit const annotation typealias this super null true false where crossinline noinline value actual expect"),
        types = words("Int Long Short Byte Float Double Boolean Char String Unit Any Nothing List Map Set Array"), lineComments = listOf("//"), blockComment = "/*" to "*/", tripleQuotes = true, annotation = '@', capitalizedTypes = true)
    val java = Language("Java", words("package import class interface enum extends implements new return if else for while do switch case default break continue try catch finally throw throws static final public private protected abstract synchronized volatile transient native this super null true false instanceof var record sealed permits yield"),
        types = cFamilyTypes, lineComments = listOf("//"), blockComment = "/*" to "*/", annotation = '@', capitalizedTypes = true)
    val swift = Language("Swift", words("import class struct enum protocol extension func var let if else guard switch case default for while repeat return break continue throw throws rethrows try catch do defer in is as self Self super nil true false init deinit static public private fileprivate internal open final override mutating async await actor some any where typealias associatedtype inout lazy weak unowned"),
        lineComments = listOf("//"), blockComment = "/*" to "*/", tripleQuotes = true, annotation = '@', capitalizedTypes = true)
    val javascript = Language("JavaScript", words("import export from default function return if else for while do switch case break continue new delete typeof instanceof in of var let const class extends super this null undefined true false try catch finally throw async await yield static get set"),
        lineComments = listOf("//"), blockComment = "/*" to "*/", quotes = "\"'`", multilineQuotes = "`", annotation = '@', capitalizedTypes = true)
    val typescript = javascript.copy(name = "TypeScript", keywords = javascript.keywords + words("interface type enum implements namespace declare readonly private public protected abstract as keyof infer never unknown any satisfies"),
        types = words("string number boolean void object symbol bigint"))
    val python = Language("Python", words("def class return if elif else for while in not and or is import from as with try except finally raise pass break continue lambda yield global nonlocal assert del None True False async await match case self"),
        lineComments = listOf("#"), tripleQuotes = true, annotation = '@', capitalizedTypes = true)
    val go = Language("Go", words("package import func return if else for range switch case default break continue go defer select chan map struct interface type var const fallthrough goto nil true false"),
        types = words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any"), lineComments = listOf("//"), blockComment = "/*" to "*/", quotes = "\"'`", multilineQuotes = "`")
    val rust = Language("Rust", words("fn let mut const static struct enum impl trait pub use mod crate self Self super if else match for while loop in return break continue as ref move where type unsafe async await dyn true false"),
        types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box"), lineComments = listOf("//"), blockComment = "/*" to "*/", annotation = '#', capitalizedTypes = true)
    val c = Language("C/C++", words("if else for while do switch case default break continue return goto struct union enum typedef static extern const volatile inline sizeof class namespace using template typename public private protected virtual override new delete this nullptr true false auto constexpr include define ifdef ifndef endif pragma"),
        types = cFamilyTypes, lineComments = listOf("//"), blockComment = "/*" to "*/", annotation = '#')
    val csharp = java.copy(name = "C#", keywords = java.keywords + words("namespace using struct internal readonly async await var get set out ref params override virtual"))
    val ruby = Language("Ruby", words("def class module end if elsif else unless case when while until for in do return yield begin rescue ensure raise self nil true false and or not require include extend attr_accessor"),
        lineComments = listOf("#"), annotation = ':', capitalizedTypes = true)
    val shell = Language("Shell", words("if then else elif fi for in do done while until case esac function return local export readonly set unset shift exit source echo cd"),
        lineComments = listOf("#"), quotes = "\"'", multilineQuotes = "\"'", annotation = '$')
    val yaml = Language("YAML", words("true false null yes no on off"), lineComments = listOf("#"), keys = true, annotation = '&')
    val json = Language("JSON", words("true false null"), keys = true)
    val toml = Language("TOML", words("true false"), lineComments = listOf("#", ";"), keys = true)
    val xml = Language("XML", blockComment = "<!--" to "-->", markup = true)
    val css = Language("CSS", words("important media import from to"), blockComment = "/*" to "*/", lineComments = listOf("//"), keys = true, annotation = '@')
    val sql = Language("SQL", words("select from where and or not insert into values update set delete create table index view drop alter add join left right inner outer on as group by order having limit offset union distinct null is in like between case when then else end primary key foreign references default"),
        lineComments = listOf("--"), blockComment = "/*" to "*/", ignoreCase = true)
    val dockerfile = Language("Dockerfile", words("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS"), lineComments = listOf("#"))
    val groovy = java.copy(name = "Groovy", keywords = java.keywords + words("def it"), tripleQuotes = true)
    val markdown = Language("Markdown", quotes = "`", headings = true)

    private val extensions = mapOf(
        kotlin to "kt kts", java to "java", swift to "swift", javascript to "js mjs cjs jsx vue", typescript to "ts tsx mts",
        python to "py pyi", go to "go", rust to "rs", c to "c h cc cpp cxx hpp hh m mm", csharp to "cs", ruby to "rb rake gemspec",
        shell to "sh bash zsh fish", yaml to "yml yaml", json to "json jsonc", toml to "toml ini cfg properties conf",
        xml to "xml html htm svg plist xib storyboard", css to "css scss sass less", sql to "sql", groovy to "groovy gradle",
        markdown to "md markdown",
    ).flatMap { (language, list) -> list.split(' ').map { it to language } }.toMap()

    private val fileNames = mapOf("dockerfile" to dockerfile, "makefile" to shell, "gemfile" to ruby, "podfile" to ruby, "jenkinsfile" to groovy, ".gitlab-ci.yml" to yaml)

    fun languageFor(fileName: String): Language? {
        val name = fileName.substringAfterLast('/').lowercase()
        fileNames[name]?.let { return it }
        if (name.startsWith("dockerfile")) return dockerfile
        if (name.startsWith(".env")) return shell
        return extensions[name.substringAfterLast('.', "")]
    }

    fun highlight(text: String, language: Language): List<SyntaxToken> {
        val tokens = mutableListOf<SyntaxToken>()
        val keywords = if (language.ignoreCase) language.keywords.map { it.lowercase() }.toSet() else language.keywords
        var i = 0
        val n = text.length
        fun add(start: Int, end: Int, kind: TokenKind) { if (end > start) tokens += SyntaxToken(start, end, kind) }
        fun endOfLine(from: Int) = text.indexOf('\n', from).let { if (it < 0) n else it }
        fun nextNonSpace(from: Int): Char? {
            var j = from
            while (j < n && (text[j] == ' ' || text[j] == '\t')) j++
            return text.getOrNull(j)
        }
        var lineStart = true
        while (i < n) {
            val ch = text[i]
            if (ch == '\n') { lineStart = true; i++; continue }
            if (language.headings && lineStart && ch == '#') {
                val end = endOfLine(i); add(i, end, TokenKind.KEYWORD); i = end; continue
            }
            if (ch != ' ' && ch != '\t') lineStart = false
            val block = language.blockComment
            if (block != null && text.startsWith(block.first, i)) {
                val close = text.indexOf(block.second, i + block.first.length)
                val end = if (close < 0) n else close + block.second.length
                add(i, end, TokenKind.COMMENT); i = end; continue
            }
            val comment = language.lineComments.firstOrNull { text.startsWith(it, i) }
            if (comment != null && (comment != "#" || i == 0 || text[i - 1].isWhitespace())) {
                val end = endOfLine(i); add(i, end, TokenKind.COMMENT); i = end; continue
            }
            if (language.markup && ch == '<') {
                var j = i + 1
                if (j < n && (text[j] == '/' || text[j] == '?' || text[j] == '!')) j++
                val nameStart = j
                while (j < n && (text[j].isLetterOrDigit() || text[j] in ":-_.")) j++
                if (j > nameStart) { add(i, j, TokenKind.TAG); i = j; continue }
            }
            if (language.markup && ch.isLetter()) {
                var j = i
                while (j < n && (text[j].isLetterOrDigit() || text[j] in ":-_")) j++
                if (j < n && text[j] == '=') { add(i, j, TokenKind.PROPERTY); i = j; continue }
            }
            if (language.tripleQuotes && (text.startsWith("\"\"\"", i) || text.startsWith("'''", i))) {
                val quote = text.substring(i, i + 3)
                val close = text.indexOf(quote, i + 3)
                val end = if (close < 0) n else close + 3
                add(i, end, TokenKind.STRING); i = end; continue
            }
            if (ch in language.quotes && !(ch == '\'' && language.markup)) {
                val multiline = ch in language.multilineQuotes
                var j = i + 1
                while (j < n && text[j] != ch && (multiline || text[j] != '\n')) j += if (text[j] == '\\') 2 else 1
                val end = minOf(n, j + 1)
                val kind = if (language.keys && nextNonSpace(end) == ':') TokenKind.PROPERTY else TokenKind.STRING
                add(i, end, kind); i = end; continue
            }
            val previousIsWord = i > 0 && (text[i - 1].isLetterOrDigit() || text[i - 1] == '_')
            if (ch.isDigit() && !previousIsWord) {
                var j = i + 1
                while (j < n && (text[j].isLetterOrDigit() || text[j] == '.' || text[j] == '_')) j++
                add(i, j, TokenKind.NUMBER); i = j; continue
            }
            if (language.annotation != null && ch == language.annotation && i + 1 < n && (text[i + 1].isLetter() || text[i + 1] == '_' || text[i + 1] == '{' || text[i + 1] == '[')) {
                var j = i + 1
                while (j < n && (text[j].isLetterOrDigit() || text[j] in "_.{}[]")) j++
                add(i, j, TokenKind.ANNOTATION); i = j; continue
            }
            if (ch.isLetter() || ch == '_') {
                var j = i + 1
                while (j < n && (text[j].isLetterOrDigit() || text[j] == '_' || (language.keys && text[j] == '-'))) j++
                if (previousIsWord) { i = j; continue }
                val word = text.substring(i, j)
                val lookup = if (language.ignoreCase) word.lowercase() else word
                val next = nextNonSpace(j)
                val kind = when {
                    language.keys && next == ':' && (j >= n || text[j] != ':' || text.getOrNull(j + 1) != ':') -> TokenKind.PROPERTY
                    lookup in keywords -> TokenKind.KEYWORD
                    word in language.types || (language.capitalizedTypes && word[0].isUpperCase()) -> TokenKind.TYPE
                    next == '(' -> TokenKind.FUNCTION
                    else -> null
                }
                if (kind != null) add(i, j, kind)
                i = j; continue
            }
            i++
        }
        return tokens
    }
}
