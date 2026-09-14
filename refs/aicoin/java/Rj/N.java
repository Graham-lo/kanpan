package Rj;

import android.view.View;
import java.util.List;
import sp.aicoin_kline.chart.Chart;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class N implements View.OnClickListener {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ int f19217a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ List f19218b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final /* synthetic */ Chart f19219c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final /* synthetic */ S.a f19220d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public final /* synthetic */ S f19221e;

    public /* synthetic */ N(int i10, List list, Chart chart, S.a aVar, S s10) {
        this.f19217a = i10;
        this.f19218b = list;
        this.f19219c = chart;
        this.f19220d = aVar;
        this.f19221e = s10;
    }

    @Override // android.view.View.OnClickListener
    public final void onClick(View view) {
        S.b(this.f19217a, this.f19218b, this.f19219c, this.f19220d, this.f19221e, view);
    }
}
