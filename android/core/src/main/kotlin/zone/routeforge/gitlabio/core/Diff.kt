package zone.routeforge.gitlabio.core

enum class DiffLineKind { HUNK, ADDED, REMOVED, CONTEXT, META }

data class DiffLine(val kind: DiffLineKind, val text: String, val oldLine: Int?, val newLine: Int?)

/** Parses the `diff` field GitLab returns per file (hunks only, no `---`/`+++` header). */
object DiffParser {
    private val hunk = Regex("^@@ -(\\d+)(?:,\\d+)? \\+(\\d+)(?:,\\d+)? @@(.*)$")

    fun parse(diff: String): List<DiffLine> {
        var old = 0
        var new = 0
        val lines = mutableListOf<DiffLine>()
        for (line in diff.removeSuffix("\n").split('\n')) {
            if (line.isEmpty() && lines.isEmpty()) continue
            val header = hunk.find(line)
            when {
                header != null -> {
                    old = header.groupValues[1].toInt()
                    new = header.groupValues[2].toInt()
                    lines += DiffLine(DiffLineKind.HUNK, line, null, null)
                }
                line.startsWith("---") || line.startsWith("+++") || line.startsWith("diff --git") -> lines += DiffLine(DiffLineKind.META, line, null, null)
                line.startsWith("+") -> lines += DiffLine(DiffLineKind.ADDED, line.substring(1), null, new++)
                line.startsWith("-") -> lines += DiffLine(DiffLineKind.REMOVED, line.substring(1), old++, null)
                line.startsWith("\\") -> lines += DiffLine(DiffLineKind.META, line, null, null)
                else -> lines += DiffLine(DiffLineKind.CONTEXT, line.removePrefix(" "), old++, new++)
            }
        }
        return lines
    }

    /** Added and removed line counts of one file diff. */
    fun stats(diff: String): Pair<Int, Int> {
        val lines = parse(diff)
        return lines.count { it.kind == DiffLineKind.ADDED } to lines.count { it.kind == DiffLineKind.REMOVED }
    }
}
