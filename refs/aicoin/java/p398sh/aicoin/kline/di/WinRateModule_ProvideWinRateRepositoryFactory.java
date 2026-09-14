package p398sh.aicoin.kline.di;

import Of.a;
import android.content.Context;
import p398sh.aicoin.kline.winrate.n;
import p478wd.b;
import p478wd.d;
import p478wd.e;
import p478wd.f;

/* JADX INFO: loaded from: classes7.dex */
public final class WinRateModule_ProvideWinRateRepositoryFactory implements b {
    private final e contextProvider;

    public WinRateModule_ProvideWinRateRepositoryFactory(e eVar) {
        this.contextProvider = eVar;
    }

    public static WinRateModule_ProvideWinRateRepositoryFactory create(a aVar) {
        return new WinRateModule_ProvideWinRateRepositoryFactory(f.a(aVar));
    }

    public static WinRateModule_ProvideWinRateRepositoryFactory create(e eVar) {
        return new WinRateModule_ProvideWinRateRepositoryFactory(eVar);
    }

    public static n provideWinRateRepository(Context context) {
        return (n) d.d(WinRateModule.INSTANCE.provideWinRateRepository(context));
    }

    @Override // Of.a
    public n get() {
        return provideWinRateRepository((Context) this.contextProvider.get());
    }
}
