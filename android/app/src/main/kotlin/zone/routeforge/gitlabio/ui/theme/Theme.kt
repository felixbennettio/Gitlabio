package zone.routeforge.gitlabio.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import zone.routeforge.gitlabio.core.TokenKind

// Brand scheme built from GitLab orange (#FC6D26) with the GitLab purple as tertiary, matching
// the iOS app. Surfaces stay near-neutral so code and diffs read cleanly. Dynamic colour is opt-in.
private val BrandLight = lightColorScheme(
    primary = Color(0xFFA33F00), onPrimary = Color.White, primaryContainer = Color(0xFFFFDBCC), onPrimaryContainer = Color(0xFF360F00),
    secondary = Color(0xFF77574A), onSecondary = Color.White, secondaryContainer = Color(0xFFFFDBCC), onSecondaryContainer = Color(0xFF2C160B),
    tertiary = Color(0xFF6B4FBB), onTertiary = Color.White, tertiaryContainer = Color(0xFFE9DDFF), onTertiaryContainer = Color(0xFF22005D),
    background = Color(0xFFFDFBFA), onBackground = Color(0xFF1F1B19), surface = Color(0xFFFDFBFA), onSurface = Color(0xFF1F1B19),
    surfaceVariant = Color(0xFFF1E4DE), onSurfaceVariant = Color(0xFF52443E), outline = Color(0xFF85736C), outlineVariant = Color(0xFFD8C2BA),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF8F4F2), surfaceContainer = Color(0xFFF3EEEC),
    surfaceContainerHigh = Color(0xFFEDE8E6), surfaceContainerHighest = Color(0xFFE7E2E0),
)

private val BrandDark = darkColorScheme(
    primary = Color(0xFFFFB596), onPrimary = Color(0xFF581E00), primaryContainer = Color(0xFF7D2E00), onPrimaryContainer = Color(0xFFFFDBCC),
    secondary = Color(0xFFE7BEAD), onSecondary = Color(0xFF442A1F), secondaryContainer = Color(0xFF5D4034), onSecondaryContainer = Color(0xFFFFDBCC),
    tertiary = Color(0xFFD0BCFF), onTertiary = Color(0xFF3A2178), tertiaryContainer = Color(0xFF523896), onTertiaryContainer = Color(0xFFE9DDFF),
    background = Color(0xFF141211), onBackground = Color(0xFFECE0DC), surface = Color(0xFF141211), onSurface = Color(0xFFECE0DC),
    surfaceVariant = Color(0xFF52443E), onSurfaceVariant = Color(0xFFD8C2BA), outline = Color(0xFFA08D86), outlineVariant = Color(0xFF52443E),
    surfaceContainerLowest = Color(0xFF0F0D0C), surfaceContainerLow = Color(0xFF1C1A19), surfaceContainer = Color(0xFF211E1D),
    surfaceContainerHigh = Color(0xFF2B2827), surfaceContainerHighest = Color(0xFF363332),
)

/** A tinted container with matching foreground, used by status pills and labels. */
@Immutable data class Tone(val container: Color, val content: Color)

enum class ToneKey { SUCCESS, DANGER, INFO, WARNING, NEUTRAL, ACCENT }

@Immutable
data class AppColors(
    val tones: Map<ToneKey, Tone>,
    val diffAdded: Color, val diffAddedGutter: Color,
    val diffRemoved: Color, val diffRemovedGutter: Color,
    val diffHunk: Color,
    val syntax: Map<TokenKind, Color>,
    val dark: Boolean,
) {
    fun tone(key: ToneKey) = tones.getValue(key)
}

private val LightApp = AppColors(
    tones = mapOf(
        ToneKey.SUCCESS to Tone(Color(0xFFD4F3DA), Color(0xFF17652B)),
        ToneKey.DANGER to Tone(Color(0xFFFFDAD6), Color(0xFF9F1A1D)),
        ToneKey.INFO to Tone(Color(0xFFD8E2FF), Color(0xFF1D4A9E)),
        ToneKey.WARNING to Tone(Color(0xFFFFE6BF), Color(0xFF734A00)),
        ToneKey.NEUTRAL to Tone(Color(0xFFE6E3EC), Color(0xFF4A4952)),
        ToneKey.ACCENT to Tone(Color(0xFFEADDFF), Color(0xFF5A2D9C)),
    ),
    diffAdded = Color(0xFFE7F7EB), diffAddedGutter = Color(0xFFCDEED5),
    diffRemoved = Color(0xFFFDECEC), diffRemovedGutter = Color(0xFFF8D3D3),
    diffHunk = Color(0xFFECEFFE),
    syntax = mapOf(
        TokenKind.KEYWORD to Color(0xFFC0262D), TokenKind.TYPE to Color(0xFF8F3E00), TokenKind.STRING to Color(0xFF0A3B78),
        TokenKind.NUMBER to Color(0xFF0B57B0), TokenKind.COMMENT to Color(0xFF6E7781), TokenKind.ANNOTATION to Color(0xFF7A47D1),
        TokenKind.FUNCTION to Color(0xFF6537B7), TokenKind.PROPERTY to Color(0xFF0B57B0), TokenKind.TAG to Color(0xFF17652B),
    ),
    dark = false,
)

private val DarkApp = AppColors(
    tones = mapOf(
        ToneKey.SUCCESS to Tone(Color(0xFF1B4627), Color(0xFF9DE2AB)),
        ToneKey.DANGER to Tone(Color(0xFF5B1B1D), Color(0xFFFFB3AC)),
        ToneKey.INFO to Tone(Color(0xFF1B3566), Color(0xFFB0C6FF)),
        ToneKey.WARNING to Tone(Color(0xFF4C3500), Color(0xFFFFCF85)),
        ToneKey.NEUTRAL to Tone(Color(0xFF393841), Color(0xFFC9C6D1)),
        ToneKey.ACCENT to Tone(Color(0xFF43296F), Color(0xFFD9BCFF)),
    ),
    diffAdded = Color(0xFF15301D), diffAddedGutter = Color(0xFF1D4027),
    diffRemoved = Color(0xFF3A191B), diffRemovedGutter = Color(0xFF4F2023),
    diffHunk = Color(0xFF1E2340),
    syntax = mapOf(
        TokenKind.KEYWORD to Color(0xFFFF7B72), TokenKind.TYPE to Color(0xFFFFA657), TokenKind.STRING to Color(0xFFA5D6FF),
        TokenKind.NUMBER to Color(0xFF79C0FF), TokenKind.COMMENT to Color(0xFF8B949E), TokenKind.ANNOTATION to Color(0xFFD2A8FF),
        TokenKind.FUNCTION to Color(0xFFD2A8FF), TokenKind.PROPERTY to Color(0xFF79C0FF), TokenKind.TAG to Color(0xFF7EE787),
    ),
    dark = true,
)

val LocalAppColors = staticCompositionLocalOf { LightApp }

object AppTheme {
    val colors: AppColors @Composable get() = LocalAppColors.current
}

val CodeFont: FontFamily = FontFamily.Monospace

@Composable
fun GitlabioTheme(dark: Boolean = isSystemInDarkTheme(), dynamicColor: Boolean = false, content: @Composable () -> Unit) {
    val scheme: ColorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(LocalContext.current) else dynamicLightColorScheme(LocalContext.current)
        dark -> BrandDark
        else -> BrandLight
    }
    CompositionLocalProvider(LocalAppColors provides if (dark) DarkApp else LightApp) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
