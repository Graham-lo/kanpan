package Rj;

import p167hg.AbstractC7609s;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class E {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final E f19079a = new E();

    public final void a(C2732n c2732n, String str, String str2) {
        C2741q c2741qB = c2732n.b();
        C2765z c2765zH = c2741qB.h(str);
        boolean z10 = c2765zH == null || !AbstractC7609s.f(c2765zH.d(), str2);
        c2741qB.c(z10);
        F f10 = new F(kk.i.a(str, ".root"));
        c2741qB.f19493a.put(f10.d(), f10);
        c2741qB.f19496d.put(f10.d(), f10);
        L0 l10 = new L0(kk.i.a(str, ".charts"));
        c2741qB.f19496d.put(l10.d(), l10);
        l10.G(C2702d.b.Fill);
        f10.I(l10);
        C2757v1 c2757v1 = C2757v1.f19568a;
        c2757v1.D(c2732n, str, l10, z10);
        KLineManager.a aVar = KLineManager.f142490O;
        c2741qB.t(aVar.a().f0() == 1 ? mk.e.f133635a.b() : mk.e.f133635a.a());
        c2757v1.A(c2732n, str, str2);
        aVar.a().A0(c2732n.b());
        aVar.a().z0(c2732n.c());
        c2741qB.f19509q = true;
    }
}
