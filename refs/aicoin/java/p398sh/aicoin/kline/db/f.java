package p398sh.aicoin.kline.db;

import java.util.List;
import kotlin.jvm.functions.Function1;
import p049c4.b;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class f implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ h f140580a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ List f140581b;

    public /* synthetic */ f(h hVar, List list) {
        this.f140580a = hVar;
        this.f140581b = list;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return this.f140580a.j(this.f140581b, (b) obj);
    }
}
