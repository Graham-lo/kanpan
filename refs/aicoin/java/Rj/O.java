package Rj;

import android.view.View;
import java.util.List;
import sp.aicoin_kline.chart.Chart;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class O implements View.OnClickListener {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ int f19223a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ List f19224b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final /* synthetic */ List f19225c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final /* synthetic */ Chart f19226d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final /* synthetic */ S.a f19227e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public final /* synthetic */ S f19228f;

    public /* synthetic */ O(int i10, List list, List list2, Chart chart, S.a aVar, S s10) {
        this.f19223a = i10;
        this.f19224b = list;
        this.f19225c = list2;
        this.f19226d = chart;
        this.f19227e = aVar;
        this.f19228f = s10;
    }

    @Override // android.view.View.OnClickListener
    public final void onClick(View view) {
        S.a(this.f19223a, this.f19224b, this.f19225c, this.f19226d, this.f19227e, this.f19228f, view);
    }
}
