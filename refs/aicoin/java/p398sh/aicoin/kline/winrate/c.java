package p398sh.aicoin.kline.winrate;

import android.content.Context;
import java.util.concurrent.TimeUnit;
import kotlin.jvm.functions.Function1;
import p099eb.b;
import p167hg.F;
import p167hg.N;
import p313og.k;
import p398sh.aicoin.kline.db.a;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final /* synthetic */ k[] f140693b = {N.h(new F(c.class, "repoCache", "getRepoCache()Lkotlin/jvm/functions/Function1;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final c f140692a = new c();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final p229kg.c f140694c = b.d(5, TimeUnit.MINUTES, new b());

    public static final e d(Context context) {
        return new e((a) p398sh.aicoin.kline.db.c.f140575a.b().invoke(context), new g(), new w(), new m(), new u());
    }

    public final Function1 b() {
        return (Function1) f140694c.getValue(this, f140693b[0]);
    }

    public final d c(Context context) {
        return (d) b().invoke(context);
    }
}
