package nk;

import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class v {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final v f134249a = new v();

    public static final int a(mk.a aVar, String str, String str2) {
        if (KLineManager.f142490O.a().V()) {
            str = str2;
        }
        return aVar.d(str);
    }

    public static final int b(mk.a aVar, String str, String str2) {
        if (!KLineManager.f142490O.a().V()) {
            str = str2;
        }
        return aVar.d(str);
    }
}
