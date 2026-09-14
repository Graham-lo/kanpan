package Rj;

import android.content.Context;
import sp.aicoin_kline.chart.Chart;

/* JADX INFO: renamed from: Rj.n, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final class C2732n {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final Context f19481a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public Chart f19482b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final C2741q f19483c = new C2741q();

    public C2732n(Context context) {
        this.f19481a = context;
    }

    public final Chart a() {
        return this.f19482b;
    }

    public final C2741q b() {
        return this.f19483c;
    }

    public final Context c() {
        return this.f19481a;
    }

    public final C2765z d() {
        return this.f19483c.h("ds0");
    }

    public final Chart e() {
        return this.f19482b;
    }

    public final void f(Chart chart) {
        this.f19482b = chart;
    }
}
