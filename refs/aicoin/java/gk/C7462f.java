package gk;

import kotlin.jvm.functions.Function1;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: renamed from: gk.f, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class C7462f implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ C7486r0 f96505a;

    public /* synthetic */ C7462f(C7486r0 c7486r0) {
        this.f96505a = c7486r0;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return C7468i.v(this.f96505a, (LargeOrderItem) obj);
    }
}
