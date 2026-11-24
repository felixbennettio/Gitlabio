package zone.routeforge.gitlabio

import android.app.Application
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import zone.routeforge.gitlabio.data.BasketChange
import zone.routeforge.gitlabio.data.ChangeBasket
import zone.routeforge.gitlabio.data.ChangeKind

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class ChangeBasketTest {
    @Test fun editsOfNewFilesStayCreates() {
        val basket = ChangeBasket()
        basket.put(1, "main", BasketChange("a.md", ChangeKind.CREATE, "one"))
        basket.put(1, "main", BasketChange("a.md", ChangeKind.UPDATE, "two", lastCommitId = "sha"))
        val change = basket.changes(1, "main").single()
        assertEquals(ChangeKind.CREATE, change.kind)
        assertEquals("two", change.content)
        assertNull(change.lastCommitId)
        assertEquals("create", basket.actions(1, "main").single().action)
    }

    @Test fun deletingNewFileDropsIt() {
        val basket = ChangeBasket()
        basket.put(1, "main", BasketChange("a.md", ChangeKind.CREATE, "one"))
        basket.put(1, "main", BasketChange("a.md", ChangeKind.DELETE))
        assertEquals(0, basket.total)
    }

    @Test fun basketsAreSeparatedByProjectAndBranch() {
        val basket = ChangeBasket()
        basket.put(1, "main", BasketChange("a", ChangeKind.UPDATE, "x", "sha1"))
        basket.put(1, "dev", BasketChange("a", ChangeKind.DELETE, lastCommitId = "sha2"))
        basket.put(2, "main", BasketChange("b", ChangeKind.CREATE, "y"))
        assertEquals(3, basket.total)
        val update = basket.actions(1, "main").single()
        assertEquals("sha1", update.lastCommitId)
        assertEquals("text", update.encoding)
        assertEquals("delete", basket.actions(1, "dev").single().action)
        basket.clear(1, "main")
        assertEquals(2, basket.total)
    }
}
