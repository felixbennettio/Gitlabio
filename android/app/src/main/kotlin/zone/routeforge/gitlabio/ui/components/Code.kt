package zone.routeforge.gitlabio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import zone.routeforge.gitlabio.core.AnsiColor
import zone.routeforge.gitlabio.core.AnsiLine
import zone.routeforge.gitlabio.core.DiffLine
import zone.routeforge.gitlabio.core.DiffLineKind
import zone.routeforge.gitlabio.core.DiffParser
import zone.routeforge.gitlabio.core.FileDiff
import zone.routeforge.gitlabio.core.Language
import zone.routeforge.gitlabio.core.Syntax
import zone.routeforge.gitlabio.core.SyntaxToken
import zone.routeforge.gitlabio.core.TokenKind
import zone.routeforge.gitlabio.ui.theme.AppColors
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.CodeFont
import zone.routeforge.gitlabio.ui.theme.ToneKey

val codeStyle = TextStyle(fontFamily = CodeFont, fontSize = 12.5.sp, lineHeight = 18.sp)

/** Source split into lines with syntax tokens mapped onto each line, computed once per text. */
class HighlightedSource(text: String, val language: Language?) {
    val lines: List<String> = text.replace("\t", "    ").removeSuffix("\n").split('\n')
    private val tokens: List<SyntaxToken> = language?.let { Syntax.highlight(lines.joinToString("\n"), it) }.orEmpty()
    private val starts: IntArray = IntArray(lines.size).also { array ->
        var offset = 0
        lines.forEachIndexed { index, line -> array[index] = offset; offset += line.length + 1 }
    }
    val longest: Int = lines.maxOfOrNull { it.length } ?: 0

    fun line(index: Int, colors: AppColors): AnnotatedString {
        val text = keepIndent(lines[index])
        if (tokens.isEmpty()) return AnnotatedString(text)
        val start = starts[index]
        val end = start + text.length
        // First token that may overlap this line.
        var low = 0
        var high = tokens.size
        while (low < high) {
            val mid = (low + high) / 2
            if (tokens[mid].end <= start) low = mid + 1 else high = mid
        }
        return buildAnnotatedString {
            append(text)
            var i = low
            while (i < tokens.size && tokens[i].start < end) {
                val token = tokens[i]
                addStyle(tokenStyle(token.kind, colors), maxOf(token.start, start) - start, minOf(token.end, end) - start)
                i++
            }
        }
    }
}

/**
 * Turns leading spaces into no-break spaces (same length, so token offsets still match). With soft
 * wrapping on, the line breaker would otherwise break after the indent and push the whole statement
 * onto the next row.
 */
fun keepIndent(line: String): String {
    val indent = line.indexOfFirst { it != ' ' }.let { if (it < 0) line.length else it }
    return if (indent == 0) line else " ".repeat(indent) + line.substring(indent)
}

fun tokenStyle(kind: TokenKind, colors: AppColors): SpanStyle {
    val color = colors.syntax[kind] ?: Color.Unspecified
    return when (kind) {
        TokenKind.COMMENT -> SpanStyle(color = color, fontStyle = FontStyle.Italic)
        TokenKind.KEYWORD, TokenKind.TAG -> SpanStyle(color = color, fontWeight = FontWeight.Medium)
        else -> SpanStyle(color = color)
    }
}

/** Highlights a short snippet (Markdown code blocks). */
fun highlightSnippet(code: String, languageName: String?, colors: AppColors): AnnotatedString {
    val language = languageName?.let { Syntax.languageFor("x.$it") ?: Syntax.languageFor(it) }
    val source = HighlightedSource(code, language)
    return buildAnnotatedString {
        source.lines.indices.forEach { index ->
            if (index > 0) append('\n')
            append(source.line(index, colors))
        }
    }
}

/** Line-numbered, highlighted source. Without [wrap] the whole block scrolls sideways. */
@Composable
fun CodeView(source: HighlightedSource, wrap: Boolean, modifier: Modifier = Modifier, state: LazyListState = rememberLazyListState()) {
    val colors = AppTheme.colors
    val gutterDigits = source.lines.size.toString().length
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val charWidth = remember(measurer) { measurer.measure("0", codeStyle).size.width }
    val gutterWidth = with(density) { (charWidth * gutterDigits).toDp() } + 20.dp
    val contentWidth = with(density) { (charWidth * (source.longest + 2)).toDp() } + gutterWidth
    val horizontal = rememberScrollState()
    Box(modifier.fillMaxSize().then(if (wrap) Modifier else Modifier.horizontalScroll(horizontal))) {
        SelectionContainer {
            LazyColumn(
                (if (wrap) Modifier.fillMaxWidth() else Modifier.width(contentWidth)).fillMaxSize(),
                state = state, contentPadding = PaddingValues(top = 8.dp, bottom = 96.dp),
            ) {
                items(source.lines.size) { index ->
                    Row(Modifier.fillMaxWidth()) {
                        Text(
                            "${index + 1}", Modifier.width(gutterWidth).padding(end = 12.dp), style = codeStyle,
                            color = MaterialTheme.colorScheme.outline, textAlign = androidx.compose.ui.text.style.TextAlign.End, maxLines = 1,
                        )
                        Text(source.line(index, colors), style = codeStyle, softWrap = wrap, modifier = Modifier.weight(1f).padding(end = 12.dp))
                    }
                }
            }
        }
    }
}

/** A diff rendered as rows of a lazy list so long merge requests stay smooth. */
data class DiffFileRows(val file: FileDiff, val lines: List<DiffLine>, val added: Int, val removed: Int)

fun prepareDiffs(files: List<FileDiff>): List<DiffFileRows> = files.map { file ->
    val lines = DiffParser.parse(file.diff)
    DiffFileRows(file, lines, lines.count { it.kind == DiffLineKind.ADDED }, lines.count { it.kind == DiffLineKind.REMOVED })
}

fun LazyListScope.diffItems(files: List<DiffFileRows>, colors: AppColors, collapsed: Set<String>, onToggle: (String) -> Unit) {
    files.forEach { rows ->
        val path = rows.file.newPath
        item(key = "file:$path") { DiffFileHeader(rows, path in collapsed) { onToggle(path) } }
        if (path in collapsed) return@forEach
        when {
            rows.file.tooLarge || rows.file.collapsed -> item(key = "big:$path") { DiffNotice("差异过大，GitLab 未返回内容。") }
            rows.lines.isEmpty() -> item(key = "empty:$path") { DiffNotice(if (rows.file.newFile || rows.file.deletedFile) "二进制或空文件" else "没有文本差异（可能只改了权限或是二进制文件）") }
            else -> items(rows.lines.size, key = { "line:$path:$it" }) { index -> DiffRow(rows.lines[index], colors) }
        }
        item(key = "gap:$path") { Spacer(Modifier.height(12.dp)) }
    }
}

@Composable
private fun DiffNotice(text: String) {
    Text(text, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun DiffFileHeader(rows: DiffFileRows, collapsed: Boolean, onToggle: () -> Unit) {
    val file = rows.file
    val badge = when {
        file.newFile -> "新增" to ToneKey.SUCCESS
        file.deletedFile -> "删除" to ToneKey.DANGER
        file.renamedFile -> "重命名" to ToneKey.INFO
        else -> null
    }
    Row(
        Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(onClick = onToggle).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Description, null, Modifier.padding(end = 8.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.weight(1f)) {
            Text(
                if (file.renamedFile) "${file.oldPath} → ${file.newPath}" else file.newPath,
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont), maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
        badge?.let { (label, tone) ->
            val colors = AppTheme.colors.tone(tone)
            Text(label, Modifier.padding(start = 8.dp).clip(RoundedCornerShape(6.dp)).background(colors.container).padding(horizontal = 6.dp, vertical = 2.dp),
                color = colors.content, style = MaterialTheme.typography.labelSmall)
        }
        Text("+${rows.added}", Modifier.padding(start = 8.dp), color = AppTheme.colors.tone(ToneKey.SUCCESS).content, style = MaterialTheme.typography.labelMedium)
        Text("−${rows.removed}", Modifier.padding(start = 4.dp), color = AppTheme.colors.tone(ToneKey.DANGER).content, style = MaterialTheme.typography.labelMedium)
        Text(if (collapsed) "展开" else "收起", Modifier.padding(start = 10.dp), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
private fun DiffRow(line: DiffLine, colors: AppColors) {
    val (background, gutter, marker) = when (line.kind) {
        DiffLineKind.ADDED -> Triple(colors.diffAdded, colors.diffAddedGutter, "+")
        DiffLineKind.REMOVED -> Triple(colors.diffRemoved, colors.diffRemovedGutter, "−")
        DiffLineKind.HUNK -> Triple(colors.diffHunk, colors.diffHunk, "")
        else -> Triple(Color.Transparent, Color.Transparent, " ")
    }
    val numberColor = MaterialTheme.colorScheme.outline
    Row(Modifier.fillMaxWidth().background(background)) {
        if (line.kind == DiffLineKind.HUNK || line.kind == DiffLineKind.META) {
            Text(line.text, Modifier.padding(horizontal = 12.dp, vertical = 3.dp), style = codeStyle,
                color = MaterialTheme.colorScheme.onSurfaceVariant, fontStyle = if (line.kind == DiffLineKind.META) FontStyle.Italic else null)
            return@Row
        }
        Row(Modifier.background(gutter)) {
            Text(line.oldLine?.toString() ?: "", Modifier.width(38.dp).padding(end = 4.dp), style = codeStyle, color = numberColor, textAlign = androidx.compose.ui.text.style.TextAlign.End)
            Text(line.newLine?.toString() ?: "", Modifier.width(38.dp).padding(end = 4.dp), style = codeStyle, color = numberColor, textAlign = androidx.compose.ui.text.style.TextAlign.End)
        }
        Text(marker, Modifier.width(16.dp).padding(start = 4.dp), style = codeStyle, color = numberColor)
        Text(keepIndent(line.text.replace("\t", "    ")), Modifier.weight(1f).padding(end = 8.dp), style = codeStyle)
    }
}

/** Terminal palette used for job logs regardless of app theme, like GitLab's own log view. */
object Terminal {
    val background = Color(0xFF16161D)
    val foreground = Color(0xFFDDDBE6)
    private val basic = listOf(
        0x2E2E38, 0xF06A6A, 0x6CCB7F, 0xE7C35E, 0x6EA6F7, 0xC68AF0, 0x5CC8D6, 0xD5D3DC,
        0x6C6B78, 0xFF8F8F, 0x8BE39C, 0xF5D87D, 0x96BEFF, 0xDAA8FF, 0x84DEE9, 0xFFFFFF,
    )

    fun color(color: AnsiColor): Color {
        if (color.rgb) return Color(0xFF000000 or color.value.toLong())
        val index = color.value
        return when {
            index < 16 -> Color(0xFF000000 or basic[index].toLong())
            index < 232 -> {
                val cube = index - 16
                val level = { v: Int -> if (v == 0) 0 else 55 + v * 40 }
                Color(level(cube / 36), level(cube / 6 % 6), level(cube % 6))
            }
            else -> (8 + (index - 232) * 10).let { Color(it, it, it) }
        }
    }

    fun render(line: AnsiLine): AnnotatedString = buildAnnotatedString {
        append(line.text)
        line.spans.forEach { span ->
            val style = span.style
            addStyle(
                SpanStyle(
                    color = style.foreground?.let(::color) ?: Color.Unspecified,
                    background = style.background?.let(::color) ?: Color.Unspecified,
                    fontWeight = if (style.bold) FontWeight.Bold else null,
                    fontStyle = if (style.italic) FontStyle.Italic else null,
                    textDecoration = if (style.underline) TextDecoration.Underline else null,
                ).let { if (style.faint) it.copy(color = foreground.copy(alpha = 0.6f)) else it },
                span.start, span.end,
            )
        }
    }
}
