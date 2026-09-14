package Rj;

import android.animation.ValueAnimator;
import android.view.animation.DecelerateInterpolator;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.Chart;

/* JADX INFO: renamed from: Rj.y0, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2764y0 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final C2732n f19605a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final p146gg.o f19606b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public double f19607c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public double f19608d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public long f19609e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public long f19610f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public String f19611g = "";

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public final ValueAnimator f19612h;

    public C2764y0(C2732n c2732n, p146gg.o oVar) {
        this.f19605a = c2732n;
        this.f19606b = oVar;
        A0 a10 = new A0();
        Double dValueOf = Double.valueOf(0.0d);
        ValueAnimator valueAnimatorOfObject = ValueAnimator.ofObject(a10, new Qf.p(dValueOf, dValueOf), new Qf.p(dValueOf, dValueOf));
        valueAnimatorOfObject.setDuration(250L);
        valueAnimatorOfObject.setStartDelay(0L);
        valueAnimatorOfObject.setInterpolator(new DecelerateInterpolator());
        valueAnimatorOfObject.addUpdateListener(new C2762x0(this));
        this.f19612h = valueAnimatorOfObject;
    }

    public static final void a(C2764y0 c2764y0, ValueAnimator valueAnimator) {
        Qf.p pVar = (Qf.p) valueAnimator.getAnimatedValue();
        c2764y0.f19607c = ((Number) pVar.c()).doubleValue();
        c2764y0.f19608d = ((Number) pVar.d()).doubleValue();
        Chart chartA = c2764y0.f19605a.a();
        if (chartA != null) {
            chartA.u();
        }
    }

    public final void b(double d10, double d11, double d12, double d13, long j10, long j11) {
        if (!this.f19612h.isRunning()) {
            StringBuilder sb2 = new StringBuilder();
            sb2.append(j10);
            sb2.append('+');
            sb2.append(j11);
            if (!AbstractC7609s.f(sb2.toString(), this.f19611g)) {
                this.f19609e = j10;
                this.f19610f = j11;
                this.f19612h.setObjectValues(new Qf.p(Double.valueOf(d10), Double.valueOf(d11)), new Qf.p(Double.valueOf(d12), Double.valueOf(d13)));
                this.f19612h.start();
                StringBuilder sb3 = new StringBuilder();
                sb3.append(j10);
                sb3.append('+');
                sb3.append(j11);
                this.f19611g = sb3.toString();
            }
        }
        if (j10 == this.f19609e && j11 == this.f19610f) {
            if (this.f19611g.length() > 0) {
                this.f19606b.invoke(Double.valueOf(this.f19607c), Double.valueOf(this.f19608d));
            }
        } else if (this.f19612h.isRunning()) {
            this.f19612h.end();
        }
    }

    public final void c() {
        if (this.f19612h.isRunning()) {
            this.f19612h.cancel();
        }
        this.f19611g = "";
    }
}
