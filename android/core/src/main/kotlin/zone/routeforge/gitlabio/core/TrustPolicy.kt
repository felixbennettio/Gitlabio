package zone.routeforge.gitlabio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import java.io.ByteArrayInputStream
import java.net.InetSocketAddress
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.Base64
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * How an account decides which server certificates to accept. Hostname verification always stays on;
 * there is deliberately no "trust everything" option.
 */
@Serializable
sealed interface TrustPolicy {
    /** The platform trust store. */
    @Serializable @SerialName("system") data object System : TrustPolicy

    /** Only chains that end in one of these user-imported CA certificates (PEM). */
    @Serializable @SerialName("ca") data class CustomCa(val certificates: List<String>) : TrustPolicy

    /** Only a leaf certificate whose SHA-256 fingerprint is listed (lowercase hex, no separators). */
    @Serializable @SerialName("pin") data class PinnedLeaf(val sha256: List<String>) : TrustPolicy

    fun apply(builder: OkHttpClient.Builder): OkHttpClient.Builder {
        val manager = when (this) {
            System -> return builder
            is CustomCa -> caTrustManager(certificates.flatMap { Certificates.parse(it.toByteArray()) })
            is PinnedLeaf -> PinnedLeafTrustManager(sha256.map(Certificates::normalizeFingerprint).toSet())
        }
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(manager), null) }
        return builder.sslSocketFactory(context.socketFactory, manager)
    }
}

private fun caTrustManager(anchors: List<X509Certificate>): X509TrustManager {
    require(anchors.isNotEmpty()) { "未导入任何 CA 证书。" }
    val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
    anchors.forEachIndexed { index, certificate -> store.setCertificateEntry("anchor-$index", certificate) }
    val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
    return factory.trustManagers.filterIsInstance<X509TrustManager>().first()
}

private class PinnedLeafTrustManager(private val pins: Set<String>) : X509TrustManager {
    init { require(pins.isNotEmpty()) { "未填写证书指纹。" } }

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
        throw CertificateException("Client certificates are not accepted")

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("Empty certificate chain")
        leaf.checkValidity()
        if (Certificates.fingerprint(leaf) !in pins) throw CertificateException("Server certificate does not match the pinned fingerprint")
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

/** What the probe saw for one certificate of a server chain. */
data class CertificateSummary(
    val subject: String,
    val issuer: String,
    val notBefore: Long,
    val notAfter: Long,
    val sha256: String,
    val isAuthority: Boolean,
)

object Certificates {
    /** Reads one or more PEM blocks, or a single DER certificate. */
    fun parse(bytes: ByteArray): List<X509Certificate> {
        val factory = CertificateFactory.getInstance("X.509")
        val text = runCatching { String(bytes, Charsets.US_ASCII) }.getOrDefault("")
        val certificates = if (text.contains("-----BEGIN CERTIFICATE-----")) {
            Regex("-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\\s]+)-----END CERTIFICATE-----").findAll(text).map {
                val der = Base64.getMimeDecoder().decode(it.groupValues[1])
                factory.generateCertificate(ByteArrayInputStream(der)) as X509Certificate
            }.toList()
        } else {
            factory.generateCertificates(ByteArrayInputStream(bytes)).filterIsInstance<X509Certificate>()
        }
        require(certificates.isNotEmpty()) { "文件中没有可识别的 X.509 证书。" }
        return certificates
    }

    fun toPem(certificate: X509Certificate): String =
        "-----BEGIN CERTIFICATE-----\n" + Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(certificate.encoded) + "\n-----END CERTIFICATE-----\n"

    fun fingerprint(certificate: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(certificate.encoded).joinToString("") { "%02x".format(it) }

    /** Accepts `AB:CD:…`, spaced or plain hex and returns lowercase hex; rejects anything that is not 32 bytes. */
    fun normalizeFingerprint(value: String): String {
        val hex = value.filterNot { it == ':' || it.isWhitespace() }.lowercase()
        require(hex.length == 64 && hex.all { it in '0'..'9' || it in 'a'..'f' }) { "SHA-256 指纹应为 64 位十六进制。" }
        return hex
    }

    /** `AB:CD:…` grouping for display. */
    fun displayFingerprint(hex: String) = hex.uppercase().chunked(2).joinToString(":")

    fun summarize(certificate: X509Certificate) = CertificateSummary(
        subject = certificate.subjectX500Principal.name,
        issuer = certificate.issuerX500Principal.name,
        notBefore = certificate.notBefore.time,
        notAfter = certificate.notAfter.time,
        sha256 = fingerprint(certificate),
        isAuthority = certificate.basicConstraints >= 0,
    )

    /**
     * Opens a TLS connection only to read the certificate chain the server presents, aborting the
     * handshake before any request is sent. The user must compare the fingerprint out of band.
     */
    fun probe(instance: GitLabInstance, timeoutMillis: Int = 10_000): List<CertificateSummary> {
        val recorder = object : X509TrustManager {
            var chain: List<X509Certificate> = emptyList()
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException()
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                this.chain = chain?.toList().orEmpty()
                throw CertificateException("Probe only")
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(recorder), null) }
        val url = instance.url
        java.net.Socket().use { raw ->
            raw.connect(InetSocketAddress(url.host, url.port), timeoutMillis)
            raw.soTimeout = timeoutMillis
            val socket = context.socketFactory.createSocket(raw, url.host, url.port, true) as SSLSocket
            socket.use { runCatching { it.startHandshake() } }
        }
        require(recorder.chain.isNotEmpty()) { "服务器没有返回证书。" }
        return recorder.chain.map(::summarize)
    }
}
