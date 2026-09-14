package nk;

import p167hg.AbstractC7609s;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class n {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final n f134230a = new n();

    public static final long c() {
        return ((long) f134230a.b()) * 1000;
    }

    public static final boolean d(int i10) {
        return KLineManager.f142490O.a().E().contains(Integer.valueOf(i10)) && f(21);
    }

    public static final boolean e(String str) {
        return KLineManager.f142490O.a().F().contains(str) && f(21);
    }

    public static final boolean f(int... iArr) {
        for (int i10 : iArr) {
            if (KLineManager.f142490O.a().q(i10) != 1) {
                return false;
            }
        }
        return true;
    }

    public static final void g(int... iArr) {
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        for (int i10 : iArr) {
            kLineManagerA.v0(i10, kLineManagerA.r(i10));
        }
    }

    public static final void h(int... iArr) {
        for (int i10 : iArr) {
            KLineManager.f142490O.a().v0(i10, 0);
        }
    }

    public static final void i(int... iArr) {
        for (int i10 : iArr) {
            KLineManager.f142490O.a().v0(i10, 1);
        }
    }

    public static final void j(int... iArr) {
        KLineManager kLineManagerA = KLineManager.f142490O.a();
        for (int i10 : iArr) {
            kLineManagerA.v0(i10, ((Number) p162hb.e.c(kLineManagerA.q(i10) == 1, 0, 1)).intValue());
        }
    }

    public final int a(String str, String str2) {
        if (AbstractC7609s.f(str2, p254m.aicoin.kline.main.menu.period.z.Sec.b())) {
            return Integer.parseInt(str);
        }
        if (AbstractC7609s.f(str2, p254m.aicoin.kline.main.menu.period.z.Min.b())) {
            return Integer.parseInt(str) * 60;
        }
        if (AbstractC7609s.f(str2, p254m.aicoin.kline.main.menu.period.z.Hour.b())) {
            return Integer.parseInt(str) * 3600;
        }
        if (AbstractC7609s.f(str2, p254m.aicoin.kline.main.menu.period.z.Day.b())) {
            return Integer.parseInt(str) * 86400;
        }
        if (AbstractC7609s.f(str2, "M")) {
            return Integer.parseInt(str) * 2592000;
        }
        if (AbstractC7609s.f(str2, "q")) {
            return Integer.parseInt(str) * 7776000;
        }
        if (AbstractC7609s.f(str2, "y")) {
            return Integer.parseInt(str) * 31536000;
        }
        return AbstractC7609s.f(str2, "rs") ? Integer.parseInt(str) : Integer.parseInt(str) * 60;
    }

    public final int b() {
        Qf.p pVarA = Zj.d.a(KLineManager.h0(KLineManager.f142490O.a(), null, 1, null));
        return a((String) pVarA.a(), (String) pVarA.b());
    }
}
