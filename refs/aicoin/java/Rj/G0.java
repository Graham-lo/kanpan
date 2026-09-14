package Rj;

import java.util.List;
import kotlin.jvm.functions.Function1;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class G0 implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ List f19130a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ H0 f19131b;

    public /* synthetic */ G0(List list, H0 h10) {
        this.f19130a = list;
        this.f19131b = h10;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return H0.H(this.f19130a, this.f19131b, ((Integer) obj).intValue());
    }
}
