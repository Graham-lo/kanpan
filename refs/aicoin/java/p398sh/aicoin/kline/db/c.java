package p398sh.aicoin.kline.db;

import P3.C2617o;
import android.content.Context;
import app.aicoin.base.kline.content.WinRateConfigDatabase;
import java.util.concurrent.TimeUnit;
import kotlin.jvm.functions.Function1;
import p099eb.b;
import p167hg.F;
import p167hg.N;
import p313og.k;

/* JADX INFO: loaded from: classes7.dex */
public final class c {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final /* synthetic */ k[] f140576b = {N.h(new F(c.class, "instance", "getInstance()Lkotlin/jvm/functions/Function1;", 0))};

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final c f140575a = new c();

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final p229kg.c f140577c = b.d(20, TimeUnit.SECONDS, new b());

    public static final a c(Context context) {
        return ((WinRateConfigDatabase) C2617o.a(context.getApplicationContext(), WinRateConfigDatabase.class, "win_rate_config.db").d()).V();
    }

    public final Function1 b() {
        return (Function1) f140577c.getValue(this, f140576b[0]);
    }
}
