package zone.routeforge.gitlabio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableHead
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.ext.task.list.items.TaskListItemMarker
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text as TextNode
import org.commonmark.node.ThematicBreak
import org.commonmark.parser.Parser
import zone.routeforge.gitlabio.ui.theme.AppColors
import zone.routeforge.gitlabio.ui.theme.AppTheme

private val parser: Parser = Parser.builder()
    .extensions(listOf(TablesExtension.create(), StrikethroughExtension.create(), TaskListItemsExtension.create()))
    .build()

private val reference = Regex("(?<![\\w/])([#!][0-9]+|@[A-Za-z0-9_][A-Za-z0-9_.-]*)")

private fun Node.children(): Sequence<Node> = generateSequence(firstChild) { it.next }

private data class InlineStyle(val link: SpanStyle, val code: SpanStyle, val reference: SpanStyle)

/** Renders GitLab-flavoured Markdown (CommonMark + tables, strikethrough, task lists) natively. */
@Composable
fun Markdown(text: String, modifier: Modifier = Modifier) {
    val document = remember(text) { parser.parse(text) }
    val scheme = MaterialTheme.colorScheme
    val styles = InlineStyle(
        link = SpanStyle(color = scheme.primary, textDecoration = TextDecoration.Underline),
        code = SpanStyle(fontFamily = zone.routeforge.gitlabio.ui.theme.CodeFont, background = scheme.surfaceContainerHighest),
        reference = SpanStyle(color = scheme.primary, fontWeight = FontWeight.Medium),
    )
    SelectionContainer(modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            document.children().forEach { Block(it, styles, 0) }
        }
    }
}

@Composable
private fun Blocks(parent: Node, styles: InlineStyle, depth: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { parent.children().forEach { Block(it, styles, depth) } }
}

@Composable
private fun Block(node: Node, styles: InlineStyle, depth: Int) {
    val typography = MaterialTheme.typography
    val colors = AppTheme.colors
    when (node) {
        is Heading -> Column {
            val style = when (node.level) {
                1 -> typography.headlineSmall
                2 -> typography.titleLarge
                3 -> typography.titleMedium
                else -> typography.titleSmall
            }
            Text(inlines(node, styles), style = style.copy(fontWeight = FontWeight.SemiBold), modifier = Modifier.padding(top = 6.dp))
            if (node.level <= 2) HorizontalDivider(Modifier.padding(top = 6.dp), color = MaterialTheme.colorScheme.outlineVariant)
        }
        is Paragraph -> Text(inlines(node, styles), style = typography.bodyMedium)
        is BulletList, is OrderedList -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            var number = (node as? OrderedList)?.markerStartNumber ?: 1
            node.children().filterIsInstance<ListItem>().forEach { item ->
                val task = (item.firstChild as? Paragraph)?.firstChild as? TaskListItemMarker
                Row {
                    Box(Modifier.width(24.dp).padding(top = 1.dp), contentAlignment = Alignment.TopStart) {
                        when {
                            task != null -> Icon(
                                if (task.isChecked) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank, if (task.isChecked) "已完成" else "未完成",
                                Modifier.size(18.dp), tint = if (task.isChecked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                            )
                            node is OrderedList -> Text("${number}.", style = typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            else -> Text(if (depth == 0) "•" else "◦", style = typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Column(Modifier.weight(1f)) { Blocks(item, styles, depth + 1) }
                }
                number++
            }
        }
        is FencedCodeBlock -> CodeBlock(node.literal.orEmpty(), node.info?.split(' ')?.firstOrNull(), colors)
        is IndentedCodeBlock -> CodeBlock(node.literal.orEmpty(), null, colors)
        is BlockQuote -> Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(3.dp).fillMaxHeight().background(MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(2.dp)))
            Column(Modifier.padding(start = 12.dp)) {
                androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant) {
                    Blocks(node, styles, depth)
                }
            }
        }
        is ThematicBreak -> HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        is TableBlock -> Table(node, styles)
        is HtmlBlock -> Text(node.literal.orEmpty().trim(), style = codeStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
        else -> if (node.firstChild != null) Blocks(node, styles, depth)
    }
}

@Composable
private fun CodeBlock(code: String, language: String?, colors: AppColors) {
    val highlighted = remember(code, language, colors) { highlightSnippet(code.trimEnd('\n'), language, colors) }
    Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
        Box(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp)) {
            Text(highlighted, style = codeStyle, softWrap = false)
        }
    }
}

@Composable
private fun Table(table: TableBlock, styles: InlineStyle) {
    val rows = table.children().flatMap { section -> section.children().filterIsInstance<TableRow>().map { it to (section is TableHead) } }.toList()
    val columns = rows.maxOfOrNull { (row, _) -> row.children().count() } ?: 0
    val widths = (0 until columns).map { column ->
        val chars = rows.maxOfOrNull { (row, _) -> plain(row.children().elementAtOrNull(column)).length } ?: 0
        (chars * 8 + 24).coerceIn(72, 260).dp
    }
    Surface(shape = RoundedCornerShape(10.dp), color = Color.Transparent, border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.horizontalScroll(rememberScrollState())) {
            rows.forEachIndexed { index, (row, header) ->
                if (index > 0) HorizontalDivider(Modifier.width(widths.fold(0.dp) { a, b -> a + b }), color = MaterialTheme.colorScheme.outlineVariant)
                Row(if (header) Modifier.background(MaterialTheme.colorScheme.surfaceContainerHigh) else Modifier) {
                    row.children().filterIsInstance<TableCell>().forEachIndexed { column, cell ->
                        Text(
                            inlines(cell, styles), Modifier.width(widths.getOrElse(column) { 96.dp }).padding(horizontal = 10.dp, vertical = 8.dp),
                            style = MaterialTheme.typography.bodySmall.copy(fontWeight = if (header) FontWeight.SemiBold else null),
                        )
                    }
                }
            }
        }
    }
}

private fun plain(node: Node?): String = when (node) {
    null -> ""
    is TextNode -> node.literal
    is Code -> node.literal
    else -> node.children().joinToString("") { plain(it) }
}

private fun inlines(node: Node, styles: InlineStyle): AnnotatedString = buildAnnotatedString { appendInlines(node, styles) }

private fun AnnotatedString.Builder.appendInlines(parent: Node, styles: InlineStyle) {
    parent.children().forEach { node ->
        when (node) {
            is TextNode -> appendReferences(node.literal, styles)
            is Code -> withStyle(styles.code) { append(" ${node.literal} ") }
            is Emphasis -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { appendInlines(node, styles) }
            is StrongEmphasis -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { appendInlines(node, styles) }
            is Strikethrough -> withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { appendInlines(node, styles) }
            is Link -> {
                val destination = node.destination.orEmpty()
                if (destination.startsWith("https://") || destination.startsWith("http://")) {
                    withLink(LinkAnnotation.Url(destination, TextLinkStyles(styles.link))) { appendInlines(node, styles) }
                } else withStyle(styles.link) { appendInlines(node, styles) }
            }
            is Image -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append("[图片：${plain(node).ifBlank { node.destination.substringAfterLast('/') }}]") }
            is SoftLineBreak -> append(' ')
            is HardLineBreak -> append('\n')
            is HtmlInline -> withStyle(styles.code) { append(node.literal) }
            is TaskListItemMarker -> Unit
            else -> appendInlines(node, styles)
        }
    }
}

private fun AnnotatedString.Builder.appendReferences(text: String, styles: InlineStyle) {
    var last = 0
    reference.findAll(text).forEach { match ->
        append(text.substring(last, match.range.first))
        withStyle(styles.reference) { append(match.value) }
        last = match.range.last + 1
    }
    append(text.substring(last))
}

/** Plain body text style for comments, kept here so screens share it. */
val commentTextStyle: TextStyle @Composable get() = MaterialTheme.typography.bodyMedium
