package p398sh.aicoin.kline.di;

import Of.a;
import android.content.Context;
import p398sh.aicoin.kline.winrate.d;
import p478wd.b;
import p478wd.e;
import p478wd.f;

/* JADX INFO: loaded from: classes7.dex */
public final class WinRateModule_ProvideWinRateCommonRepositoryFactory implements b {
    private final e contextProvider;

    public WinRateModule_ProvideWinRateCommonRepositoryFactory(e eVar) {
        this.contextProvider = eVar;
    }

    public static WinRateModule_ProvideWinRateCommonRepositoryFactory create(a aVar) {
        return new WinRateModule_ProvideWinRateCommonRepositoryFactory(f.a(aVar));
    }

    public static WinRateModule_ProvideWinRateCommonRepositoryFactory create(e eVar) {
        return new WinRateModule_ProvideWinRateCommonRepositoryFactory(eVar);
    }

    public static d provideWinRateCommonRepository(Context context) {
        return (d) p478wd.d.d(WinRateModule.INSTANCE.provideWinRateCommonRepository(context));
    }

    @Override // Of.a
    public d get() {
        return provideWinRateCommonRepository((Context) this.contextProvider.get());
    }
}
