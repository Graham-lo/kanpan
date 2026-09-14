package fk;

import kotlin.jvm.functions.Function1;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class H implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ I f95068a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ int f95069b;

    public /* synthetic */ H(I i10, int i11) {
        this.f95068a = i10;
        this.f95069b = i11;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return Integer.valueOf(I.a(this.f95068a, this.f95069b, (LargeOrderItem) obj));
    }
}
