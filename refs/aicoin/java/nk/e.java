package nk;

import Rj.C2741q;
import java.util.ArrayList;
import java.util.Iterator;

/* JADX INFO: loaded from: classes7.dex */
public final class e {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final Object f134197a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final ArrayList f134198b = new ArrayList();

    public e(Object obj) {
        this.f134197a = obj;
    }

    public final void a(C2741q c2741q, Object obj) {
        Iterator it = this.f134198b.iterator();
        if (it.hasNext()) {
            android.support.v4.media.a.a(it.next());
            throw null;
        }
    }

    public final boolean b() {
        return !this.f134198b.isEmpty();
    }
}
