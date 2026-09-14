package Rj;

import sp.aicoin_kline.chart.Chart;

/* JADX INFO: renamed from: Rj.m, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class RunnableC2729m implements Runnable {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ Chart f19479a;

    public /* synthetic */ RunnableC2729m(Chart chart) {
        this.f19479a = chart;
    }

    @Override // java.lang.Runnable
    public final void run() {
        Chart.b(this.f19479a);
    }
}
