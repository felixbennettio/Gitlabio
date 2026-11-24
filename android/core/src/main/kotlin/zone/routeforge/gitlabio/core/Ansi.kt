package zone.routeforge.gitlabio.core

/** A run of characters with one SGR style. Colors are 0–255 palette indexes or 0xRRGGBB when [AnsiColor.rgb]. */
data class AnsiSpan(val start: Int, val end: Int, val style: AnsiStyle)

data class AnsiColor(val value: Int, val rgb: Boolean = false)

data class AnsiStyle(
    val foreground: AnsiColor? = null,
    val background: AnsiColor? = null,
    val bold: Boolean = false,
    val italic: Boolean = false,
    val underline: Boolean = false,
    val faint: Boolean = false,
) {
    val isPlain get() = this == AnsiStyle()
}

data class AnsiLine(val text: String, val spans: List<AnsiSpan>, val section: String? = null)

/**
 * Turns a GitLab job log into styled lines: SGR colors are kept, other escape sequences and
 * GitLab's `section_start`/`section_end` markers are removed, and carriage returns keep only the
 * last overwrite of a line, the way a terminal shows progress output.
 */
object AnsiParser {
    private val sectionMarker = Regex("section_(start|end):\\d+:([A-Za-z0-9_.-]+)(\\[[^\\]]*])?\r?")

    fun parse(log: String): List<AnsiLine> {
        var style = AnsiStyle()
        val lines = mutableListOf<AnsiLine>()
        for (rawLine in log.removeSuffix("\n").split('\n')) {
            var line = rawLine.removeSuffix("\r")
            var section: String? = null
            sectionMarker.find(line)?.let { match ->
                if (match.groupValues[1] == "start") section = match.groupValues[2]
                line = line.removeRange(match.range)
            }
            // A carriage return rewinds to column 0; terminals show only what was written last.
            if ('\r' in line) line = line.substringAfterLast('\r')
            val text = StringBuilder()
            val spans = mutableListOf<AnsiSpan>()
            var spanStart = 0
            fun close() {
                if (text.length > spanStart && !style.isPlain) spans += AnsiSpan(spanStart, text.length, style)
                spanStart = text.length
            }
            var index = 0
            while (index < line.length) {
                val char = line[index]
                if (char == '\u001B' && index + 1 < line.length && line[index + 1] == '[') {
                    var end = index + 2
                    while (end < line.length && line[end] !in '@'..'~') end++
                    if (end >= line.length) break
                    if (line[end] == 'm') {
                        close()
                        style = apply(style, line.substring(index + 2, end))
                    }
                    index = end + 1
                    continue
                }
                if (char == '\u001B') { index += 2; continue }
                if (char >= ' ' || char == '\t') text.append(char)
                index++
            }
            close()
            lines += AnsiLine(text.toString(), spans, section)
        }
        return lines
    }

    internal fun apply(current: AnsiStyle, parameters: String): AnsiStyle {
        val codes = if (parameters.isEmpty()) listOf(0) else parameters.split(';').map { it.toIntOrNull() ?: 0 }
        var style = current
        var i = 0
        while (i < codes.size) {
            when (val code = codes[i]) {
                0 -> style = AnsiStyle()
                1 -> style = style.copy(bold = true)
                2 -> style = style.copy(faint = true)
                3 -> style = style.copy(italic = true)
                4 -> style = style.copy(underline = true)
                22 -> style = style.copy(bold = false, faint = false)
                23 -> style = style.copy(italic = false)
                24 -> style = style.copy(underline = false)
                in 30..37 -> style = style.copy(foreground = AnsiColor(code - 30))
                39 -> style = style.copy(foreground = null)
                in 40..47 -> style = style.copy(background = AnsiColor(code - 40))
                49 -> style = style.copy(background = null)
                in 90..97 -> style = style.copy(foreground = AnsiColor(code - 90 + 8))
                in 100..107 -> style = style.copy(background = AnsiColor(code - 100 + 8))
                38, 48 -> {
                    var color: AnsiColor? = null
                    when (codes.getOrNull(i + 1)) {
                        5 -> {
                            color = codes.getOrNull(i + 2)?.let { AnsiColor(it.coerceIn(0, 255)) }
                            i += 2
                        }
                        2 -> {
                            if (i + 4 < codes.size) {
                                val (r, g, b) = codes.subList(i + 2, i + 5).map { it.coerceIn(0, 255) }
                                color = AnsiColor((r shl 16) or (g shl 8) or b, rgb = true)
                            }
                            i += 4
                        }
                    }
                    style = if (code == 38) style.copy(foreground = color) else style.copy(background = color)
                }
            }
            i++
        }
        return style
    }
}
