package Rj;

import kotlin.jvm.functions.Function1;
import sp.aicoin_kline.chart.data.AISRLItem;

/* JADX INFO: renamed from: Rj.w, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class C2758w implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ AISRLItem f19570a;

    public /* synthetic */ C2758w(AISRLItem aISRLItem) {
        this.f19570a = aISRLItem;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return Boolean.valueOf(C2765z.o(this.f19570a, (AISRLItem) obj));
    }
}
