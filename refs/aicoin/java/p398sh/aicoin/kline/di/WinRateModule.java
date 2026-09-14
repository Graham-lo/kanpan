package p398sh.aicoin.kline.di;

import android.content.Context;
import com.umeng.analytics.pro.d;
import dagger.hilt.android.qualifiers.ApplicationContext;
import kotlin.Metadata;
import p398sh.aicoin.kline.db.a;
import p398sh.aicoin.kline.winrate.WinRateSource;
import p398sh.aicoin.kline.winrate.c;
import p398sh.aicoin.kline.winrate.h;
import p398sh.aicoin.kline.winrate.k;
import p398sh.aicoin.kline.winrate.n;
import p398sh.aicoin.kline.winrate.o;

/* JADX INFO: loaded from: classes7.dex */
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\bÇ\u0002\u0018\u00002\u00020\u0001B\t\b\u0002¢\u0006\u0004\b\u0002\u0010\u0003J\u0019\u0010\u0007\u001a\u00020\u00062\b\b\u0001\u0010\u0005\u001a\u00020\u0004H\u0007¢\u0006\u0004\b\u0007\u0010\bJ\u0019\u0010\n\u001a\u00020\t2\b\b\u0001\u0010\u0005\u001a\u00020\u0004H\u0007¢\u0006\u0004\b\n\u0010\u000b¨\u0006\f"}, d2 = {"Lsh/aicoin/kline/di/WinRateModule;", "", "<init>", "()V", "Landroid/content/Context;", d.f89950R, "Lsh/aicoin/kline/winrate/n;", "provideWinRateRepository", "(Landroid/content/Context;)Lsh/aicoin/kline/winrate/n;", "Lsh/aicoin/kline/winrate/d;", "provideWinRateCommonRepository", "(Landroid/content/Context;)Lsh/aicoin/kline/winrate/d;", "sh-kline_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final class WinRateModule {
    public static final WinRateModule INSTANCE = new WinRateModule();

    private WinRateModule() {
    }

    public final p398sh.aicoin.kline.winrate.d provideWinRateCommonRepository(@ApplicationContext Context context) {
        return c.f140692a.c(context);
    }

    public final n provideWinRateRepository(@ApplicationContext Context context) {
        return new o((a) p398sh.aicoin.kline.db.c.f140575a.b().invoke(context), new WinRateSource(), new k(), new h());
    }
}
