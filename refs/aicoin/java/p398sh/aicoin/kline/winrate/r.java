package p398sh.aicoin.kline.winrate;

import java.util.List;
import kotlin.jvm.functions.Function1;
import org.json.JSONArray;

/* JADX INFO: loaded from: classes7.dex */
public final /* synthetic */ class r implements Function1 {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final /* synthetic */ JSONArray f140742a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final /* synthetic */ List f140743b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public final /* synthetic */ WinRateSource f140744c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public final /* synthetic */ List f140745d;

    public /* synthetic */ r(JSONArray jSONArray, List list, WinRateSource winRateSource, List list2) {
        this.f140742a = jSONArray;
        this.f140743b = list;
        this.f140744c = winRateSource;
        this.f140745d = list2;
    }

    @Override // kotlin.jvm.functions.Function1
    public final Object invoke(Object obj) {
        return WinRateSource.e(this.f140742a, this.f140743b, this.f140744c, this.f140745d, ((Integer) obj).intValue());
    }
}
