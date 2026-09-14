package p398sh.aicoin.kline.tools;

import android.content.Context;
import p162hb.a;

/* JADX INFO: loaded from: classes7.dex */
public abstract class g {
    public static final Context a(a aVar) {
        Context contextB = a.b();
        if (contextB != null) {
            return contextB;
        }
        throw new IllegalStateException("AppState " + aVar + " not attached to a context.");
    }
}
