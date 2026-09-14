package Rj;

import java.util.List;
import sp.aicoin_kline.chart.Chart;

/* JADX INFO: renamed from: Rj.l, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class RunnableC2726l implements Runnable {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ Chart f19446a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ List f19447b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final /* synthetic */ X f19448c;

    public /* synthetic */ RunnableC2726l(Chart chart, List list, X x10) {
        this.f19446a = chart;
        this.f19447b = list;
        this.f19448c = x10;
    }

    @Override // java.lang.Runnable
    public final void run() {
        Chart.c(this.f19446a, this.f19447b, this.f19448c);
    }
}
