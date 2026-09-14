package fk;

import java.util.List;
import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class f0 implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ List f95384a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ g0 f95385b;

    public /* synthetic */ f0(List list, g0 g0Var) {
        this.f95384a = list;
        this.f95385b = g0Var;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return g0.H(this.f95384a, this.f95385b, ((Integer) obj).intValue());
    }
}
