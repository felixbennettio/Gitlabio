package zone.routeforge.gitlabio.core

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Test
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException
import kotlin.test.*

class TrustPolicyTest {
    private val root = HeldCertificate.Builder().certificateAuthority(0).commonName("Fixture Root CA").build()
    private val otherRoot = HeldCertificate.Builder().certificateAuthority(0).commonName("Unrelated CA").build()
    private val leaf = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(root).build()
    private val wrongHost = HeldCertificate.Builder().commonName("other.test").addSubjectAlternativeName("other.test").build()
    private val server = MockWebServer()

    @After fun cleanup() { server.shutdown() }

    private fun serve(certificate: HeldCertificate, vararg intermediates: HeldCertificate) {
        val certificates = HandshakeCertificates.Builder().heldCertificate(certificate, *intermediates.map { it.certificate }.toTypedArray()).build()
        server.useHttps(certificates.sslSocketFactory(), false)
        server.enqueue(MockResponse().setBody(fixture("user.json")))
        server.start()
    }

    private fun client(policy: TrustPolicy) = GitLabClient(GitLabInstance(server.url("/").toString()), "test-only", policy)

    @Test fun systemTrustRejectsPrivateCa() = runBlocking {
        serve(leaf, root)
        val error = assertFailsWith<SSLHandshakeException> { client(TrustPolicy.System).currentUser() }
        assertTrue(describeError(error).contains("证书不受信任"))
        assertEquals(0, server.requestCount)
    }

    @Test fun importedCaIsTrusted() = runBlocking {
        serve(leaf, root)
        val policy = TrustPolicy.CustomCa(listOf(root.certificatePem()))
        assertEquals("fixture.user", client(policy).currentUser().username)
    }

    @Test fun unrelatedCaIsRejected() = runBlocking {
        serve(leaf, root)
        assertFailsWith<SSLHandshakeException> { client(TrustPolicy.CustomCa(listOf(otherRoot.certificatePem()))).currentUser() }
        assertEquals(0, server.requestCount)
    }

    @Test fun pinnedLeafFingerprintIsTrusted() = runBlocking {
        serve(leaf, root)
        val pin = Certificates.displayFingerprint(Certificates.fingerprint(leaf.certificate))
        assertEquals("fixture.user", client(TrustPolicy.PinnedLeaf(listOf(pin))).currentUser().username)
    }

    @Test fun mismatchedPinIsRejected() = runBlocking {
        serve(leaf, root)
        val wrong = Certificates.fingerprint(otherRoot.certificate)
        assertFailsWith<SSLHandshakeException> { client(TrustPolicy.PinnedLeaf(listOf(wrong))).currentUser() }
        assertEquals(0, server.requestCount)
    }

    @Test fun pinningKeepsHostnameVerification() = runBlocking {
        serve(wrongHost)
        val pin = Certificates.fingerprint(wrongHost.certificate)
        assertFailsWith<SSLPeerUnverifiedException> { client(TrustPolicy.PinnedLeaf(listOf(pin))).currentUser() }
        assertEquals(0, server.requestCount)
    }

    @Test fun probeReportsChainWithoutSendingRequests() {
        serve(leaf, root)
        val chain = Certificates.probe(GitLabInstance(server.url("/").toString()))
        assertEquals(Certificates.fingerprint(leaf.certificate), chain.first().sha256)
        assertFalse(chain.first().isAuthority)
        assertTrue(chain.any { it.isAuthority && it.subject.contains("Fixture Root CA") })
        assertEquals(0, server.requestCount)
    }

    @Test fun certificatesParseFromPemAndDer() {
        val pem = root.certificatePem() + otherRoot.certificatePem()
        assertEquals(2, Certificates.parse(pem.toByteArray()).size)
        assertEquals(1, Certificates.parse(root.certificate.encoded).size)
        val roundTrip = Certificates.parse(Certificates.toPem(leaf.certificate).toByteArray()).single()
        assertEquals(leaf.certificate, roundTrip)
        assertFails { Certificates.parse("hello".toByteArray()) }
    }

    @Test fun fingerprintsAreNormalized() {
        val hex = "ab".repeat(32)
        assertEquals(hex, Certificates.normalizeFingerprint(Certificates.displayFingerprint(hex)))
        assertEquals(hex, Certificates.normalizeFingerprint(" AB AB ".repeat(16)))
        assertFailsWith<IllegalArgumentException> { Certificates.normalizeFingerprint("abcd") }
        assertFailsWith<IllegalArgumentException> { Certificates.normalizeFingerprint("zz".repeat(32)) }
        assertFailsWith<IllegalArgumentException> { TrustPolicy.PinnedLeaf(emptyList()).apply(okhttp3.OkHttpClient.Builder()) }
    }

    @Test fun policiesSurviveSerialization() {
        val policies = listOf(TrustPolicy.System, TrustPolicy.CustomCa(listOf(root.certificatePem())), TrustPolicy.PinnedLeaf(listOf("ab".repeat(32))))
        policies.forEach { policy ->
            val text = Json.encodeToString(TrustPolicy.serializer(), policy)
            assertEquals(policy, Json.decodeFromString(TrustPolicy.serializer(), text))
        }
    }
}
