package p398sh.aicoin.kline.winrate;

import kotlin.jvm.functions.Function1;
import org.json.JSONObject;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class s implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ p f140746a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ WinRateSource f140747b;

    public /* synthetic */ s(p pVar, WinRateSource winRateSource) {
        this.f140746a = pVar;
        this.f140747b = winRateSource;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return WinRateSource.a.t(this.f140746a, this.f140747b, (JSONObject) obj);
    }
}
