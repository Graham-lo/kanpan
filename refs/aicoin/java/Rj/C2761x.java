package Rj;

import kotlin.jvm.functions.Function1;
import sp.aicoin_kline.chart.data.AISRLItem;

/* JADX INFO: renamed from: Rj.x, reason: case insensitive filesystem */
/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class C2761x implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ AISRLItem f19601a;

    public /* synthetic */ C2761x(AISRLItem aISRLItem) {
        this.f19601a = aISRLItem;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return Boolean.valueOf(C2765z.q(this.f19601a, (AISRLItem) obj));
    }
}
