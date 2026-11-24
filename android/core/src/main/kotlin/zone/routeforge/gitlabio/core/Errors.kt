package zone.routeforge.gitlabio.core

import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.cert.CertificateException
import javax.net.ssl.SSLException
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException

/** A non-2xx response. The server body is never carried along so nothing it says reaches the UI verbatim. */
class ApiException(val status: Int) : Exception(when (status) {
    in 300..399 -> "服务器要求重定向（HTTP $status）。为保护令牌不跟随重定向，请填写实例的最终 HTTPS 地址。"
    401 -> "登录已过期或令牌无效，请更新账户凭证。"
    403 -> "没有操作权限，请检查账户角色、令牌范围和分支保护。"
    404 -> "内容不存在、当前账户不可见，或实例不支持此接口。"
    405 -> "当前状态不允许此操作（例如合并请求还不能合并）。"
    400, 409 -> "服务器拒绝更改，可能存在编辑冲突或输入无效。草稿已保留，请核对后重试。"
    422 -> "服务器无法处理此请求，请检查输入。"
    429 -> "请求过于频繁，请稍后重试。"
    in 500..599 -> "GitLab 服务器出错（HTTP $status），请稍后重试。"
    else -> "GitLab 请求失败（HTTP $status）。"
})

class ResponseTooLargeException : IOException("响应过大，已停止读取。")

/** A short, user-facing explanation of any failure from [GitLabApi] without echoing server text. */
fun describeError(error: Throwable): String = when (error) {
    is ApiException, is ResponseTooLargeException -> error.message!!
    is IllegalArgumentException, is IllegalStateException -> error.message ?: "输入无效。"
    is SSLPeerUnverifiedException -> "服务器证书与实例域名不匹配。"
    is SSLHandshakeException -> if (error.hasCause<CertificateException>()) {
        "服务器证书不受信任。若是自建实例，请在账户的证书信任中导入 CA 或固定证书指纹。"
    } else "TLS 握手失败，请检查实例地址与网络。"
    is SSLException -> "安全连接中断，请稍后重试。"
    is UnknownHostException -> "无法解析实例域名，请检查地址或网络。"
    is ConnectException -> "无法连接到服务器。"
    is SocketTimeoutException -> "连接超时，请检查网络。"
    is IOException -> "网络错误，请检查连接后重试。"
    else -> "发生错误：${error::class.simpleName}"
}

private inline fun <reified T : Throwable> Throwable.hasCause(): Boolean {
    var current: Throwable? = this
    while (current != null) {
        if (current is T) return true
        current = current.cause
    }
    return false
}

/** What a personal access token is allowed to do, derived from its scopes. */
data class TokenCapabilities(val scopes: List<String>) {
    val canRead get() = "api" in scopes || "read_api" in scopes
    val canWrite get() = "api" in scopes
    val canReadRepository get() = canRead || "read_repository" in scopes

    /** Shortcomings worth telling the user about before they save the account. */
    val warnings: List<String> get() = buildList {
        if (!canRead) add("令牌缺少 api 或 read_api 范围，无法读取项目与协作数据。")
        else if (!canWrite) add("令牌只有只读范围（read_api）：评论、批准、合并、提交和流水线操作会被拒绝。")
    }
}
