package Rj;

import android.graphics.Canvas;
import sp.aicoin_kline.chart.viewmodel.OutSideIndicData;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: renamed from: Rj.i, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2717i extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final int f19422l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final C2723k f19423m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final C2714h f19424n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final bk.a f19425o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public OutSideIndicData f19426p;

    /* JADX INFO: renamed from: q, reason: collision with root package name */
    public AbstractC2759w0 f19427q;

    /* JADX INFO: renamed from: r, reason: collision with root package name */
    public final AbstractC2744r0[] f19428r;

    public C2717i(C2732n c2732n, String str, boolean z10) {
        super(c2732n, str);
        this.f19422l = KLineManager.f142490O.a().q(14);
        C2723k c2723k = new C2723k(c2732n, str);
        this.f19423m = c2723k;
        C2714h c2714h = new C2714h(c2732n, str);
        this.f19424n = c2714h;
        bk.a aVar = new bk.a(c2732n, str);
        this.f19425o = aVar;
        this.f19428r = new AbstractC2744r0[]{c2723k, c2714h, aVar};
        aVar.v(false);
        s(z10);
        c2723k.s(z10);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        y1 y1VarK = j().k();
        if (y1VarK == null) {
            return;
        }
        float fU = y1VarK.u();
        int i10 = this.f19422l;
        if (i10 != 0) {
            if (i10 != 1) {
                if (i10 == 2) {
                    this.f19423m.g(canvas);
                }
            } else if (fU < 7.0f) {
                this.f19424n.g(canvas);
            } else {
                this.f19423m.g(canvas);
            }
        } else if (fU < 5.0f) {
            this.f19425o.g(canvas);
        } else if (fU < 7.0f) {
            this.f19424n.g(canvas);
        } else {
            this.f19423m.g(canvas);
        }
        AbstractC2759w0 abstractC2759w0L = i().b().l(b());
        this.f19427q = abstractC2759w0L;
        if (abstractC2759w0L != null) {
            OutSideIndicData outSideIndicData = this.f19426p;
            if (outSideIndicData != null) {
                outSideIndicData.setMaxValue(abstractC2759w0L.u());
            }
            OutSideIndicData outSideIndicData2 = this.f19426p;
            if (outSideIndicData2 != null) {
                AbstractC2759w0 abstractC2759w0 = this.f19427q;
                outSideIndicData2.setMinValue(abstractC2759w0 != null ? abstractC2759w0.v() : 0.0d);
            }
            OutSideIndicData outSideIndicData3 = this.f19426p;
            if (outSideIndicData3 != null) {
                AbstractC2759w0 abstractC2759w1 = this.f19427q;
                outSideIndicData3.setMaxValueY(abstractC2759w1 != null ? abstractC2759w1.S(abstractC2759w1.u()) : 0.0f);
            }
            OutSideIndicData outSideIndicData4 = this.f19426p;
            if (outSideIndicData4 != null) {
                AbstractC2759w0 abstractC2759w2 = this.f19427q;
                outSideIndicData4.setMinValueY(abstractC2759w2 != null ? abstractC2759w2.S(abstractC2759w2.v()) : 0.0f);
            }
            OutSideIndicData outSideIndicData5 = this.f19426p;
            if (outSideIndicData5 != null) {
                outSideIndicData5.setStartTime(y1VarK.F());
            }
            OutSideIndicData outSideIndicData6 = this.f19426p;
            if (outSideIndicData6 != null) {
                outSideIndicData6.setEndTime(y1VarK.n());
            }
            OutSideIndicData outSideIndicData7 = this.f19426p;
            if (outSideIndicData7 != null) {
                outSideIndicData7.setWindowStartOffset(y1VarK.J());
            }
            OutSideIndicData outSideIndicData8 = this.f19426p;
            if (outSideIndicData8 != null) {
                C2738p.f19487a.w(outSideIndicData8);
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
        for (AbstractC2744r0 abstractC2744r0 : this.f19428r) {
            abstractC2744r0.t();
        }
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
        for (AbstractC2744r0 abstractC2744r0 : this.f19428r) {
            abstractC2744r0.u(aVar);
        }
        this.f19426p = new OutSideIndicData(0.0d, 0.0d, 0.0f, 0.0f, 0L, 0L, 0, 0, 0.0f, 511, null);
    }
}
