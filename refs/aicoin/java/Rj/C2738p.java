package Rj;

import java.lang.ref.WeakReference;
import sp.aicoin_kline.chart.data.AISRLInfo;
import sp.aicoin_kline.chart.data.AIWinRateItem;
import sp.aicoin_kline.chart.data.AlertLineItem;
import sp.aicoin_kline.chart.data.DataItemClickInfo;
import sp.aicoin_kline.chart.data.LargeOrderInfo;
import sp.aicoin_kline.chart.data.LargeTradeInfo;
import sp.aicoin_kline.chart.viewmodel.OutSideIndicData;

/* JADX INFO: renamed from: Rj.p, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2738p {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final C2738p f19487a = new C2738p();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static WeakReference f19488b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static WeakReference f19489c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static WeakReference f19490d;

    /* JADX INFO: renamed from: Rj.p$a */
    public interface a {
        void b();
    }

    /* JADX INFO: renamed from: Rj.p$b */
    public interface b {
        void B(Sj.j jVar);

        void J(Sj.f fVar, int i10, int i11);

        void K();

        void N(AISRLInfo aISRLInfo);

        void P(AIWinRateItem aIWinRateItem);

        void U();

        void W(DataItemClickInfo dataItemClickInfo);

        void a0(String str, boolean z10);

        void c0();

        void d0(OutSideIndicData outSideIndicData);

        void d1(String str, boolean z10);

        void g0();

        void g1(String str);

        void h1(AlertLineItem alertLineItem);

        void k0(LargeTradeInfo largeTradeInfo);

        void l1(LargeOrderInfo largeOrderInfo);

        void m1(double d10, String str, String str2);

        void s(AlertLineItem alertLineItem);

        void u();
    }

    /* JADX INFO: renamed from: Rj.p$c */
    public interface c {
        void a();
    }

    public static final void m() {
        a aVar;
        WeakReference weakReference = f19489c;
        if (weakReference == null || (aVar = (a) weakReference.get()) == null) {
            return;
        }
        aVar.b();
    }

    public static final void p() {
        c cVar;
        WeakReference weakReference = f19490d;
        if (weakReference == null || (cVar = (c) weakReference.get()) == null) {
            return;
        }
        cVar.a();
    }

    public final void a(AISRLInfo aISRLInfo) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.N(aISRLInfo);
    }

    public final void b(double d10, String str, String str2) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.m1(d10, str, str2);
    }

    public final void c(AlertLineItem alertLineItem) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.s(alertLineItem);
    }

    public final void d(AlertLineItem alertLineItem) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.h1(alertLineItem);
    }

    public final void e(DataItemClickInfo dataItemClickInfo) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.W(dataItemClickInfo);
    }

    public final void f() {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.g0();
    }

    public final void g() {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.c0();
    }

    public final void h() {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.u();
    }

    public final void i(String str, boolean z10) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.a0(str, z10);
    }

    public final void j(String str, boolean z10) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.d1(str, z10);
    }

    public final void k(LargeOrderInfo largeOrderInfo) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.l1(largeOrderInfo);
    }

    public final void l(LargeTradeInfo largeTradeInfo) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.k0(largeTradeInfo);
    }

    public final void n(Sj.j jVar) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.B(jVar);
    }

    public final void o(String str) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.g1(str);
    }

    public final void q(Sj.f fVar, int i10, int i11) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.J(fVar, i10, i11);
    }

    public final void r() {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.U();
    }

    public final void s() {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.K();
    }

    public final void t(AIWinRateItem aIWinRateItem) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.P(aIWinRateItem);
    }

    public final void u(b bVar) {
        f19488b = bVar != null ? new WeakReference(bVar) : null;
    }

    public final void v(a aVar) {
        f19489c = aVar != null ? new WeakReference(aVar) : null;
    }

    public final void w(OutSideIndicData outSideIndicData) {
        b bVar;
        WeakReference weakReference = f19488b;
        if (weakReference == null || (bVar = (b) weakReference.get()) == null) {
            return;
        }
        bVar.d0(outSideIndicData);
    }

    public final void x(c cVar) {
        f19490d = cVar != null ? new WeakReference(cVar) : null;
    }
}
