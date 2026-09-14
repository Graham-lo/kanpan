package gk;

import kotlin.jvm.functions.Function1;
import sp.aicoin_kline.chart.data.LargeOrderItem;

/* JADX INFO: renamed from: gk.h, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class C7466h implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ C7486r0 f96510a;

    public /* synthetic */ C7466h(C7486r0 c7486r0) {
        this.f96510a = c7486r0;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return C7468i.s(this.f96510a, (LargeOrderItem) obj);
    }
}
