package fk;

import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class Q implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ S f95127a;

    public /* synthetic */ Q(S s10) {
        this.f95127a = s10;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return S.H(this.f95127a, ((Integer) obj).intValue());
    }
}
